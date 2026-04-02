import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:flutter/services.dart' show rootBundle;

class VisionTestScreen extends StatefulWidget {
  const VisionTestScreen({super.key});

  @override
  State<VisionTestScreen> createState() => _VisionTestScreenState();
}

class _VisionTestScreenState extends State<VisionTestScreen> {
  CameraController? _cameraController;
  Interpreter? _interpreter;
  List<String> _labels = [];

  bool _isProcessing = false;
  List<Map<String, dynamic>> _recognitions = [];

  // Assuming standard YOLOv8 input size is 640x640
  final int _inputSize = 640;

  // Pre-allocated tensors to prevent GC thrashing frame-by-frame
  late final List<List<List<List<double>>>> _inputTensor;
  late final List<List<List<double>>> _outputTensor;

  @override
  void initState() {
    super.initState();

    // Globally pre-allocate the TFLite tensors once.
    _inputTensor = List.generate(
      1,
      (index) => List.generate(
        _inputSize,
        (y) => List.generate(
          _inputSize,
          (x) => List.filled(3, 0.0), // Pre-allocated RGB list
        ),
      ),
    );

    _outputTensor = List.generate(
      1,
      (index) => List.generate(
        84, // YOLOv8 nano features for COCO (cx, cy, w, h, + 80 classes)
        (i) => List.filled(8400, 0.0),
      ),
    );

    _loadModelAndLabels();
    _initCamera();
  }

  Future<void> _loadModelAndLabels() async {
    try {
      // Initialize the TFLite interpreter with the YOLOv8 model
      _interpreter = await Interpreter.fromAsset('assets/yolov8n.tflite');

      // Load labels from the text file
      final labelData = await rootBundle.loadString('assets/labels.txt');
      _labels = labelData
          .split('\n')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();

      debugPrint("Model and labels loaded successfully.");
    } catch (e) {
      debugPrint("Error loading model or labels: $e");
    }
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      // Select the back camera for environment sensing
      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first, // Fallback if no back camera found
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.medium, // Medium/Low required for high FPS inference
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();
      if (!mounted) return;

      // Start the live preview stream
      _cameraController!.startImageStream((CameraImage image) {
        if (!_isProcessing) {
          _processCameraImage(image);
        }
      });

      setState(() {});
    } catch (e) {
      debugPrint("Camera initialization error: $e");
    }
  }

  Future<void> _processCameraImage(CameraImage image) async {
    _isProcessing = true;

    if (_interpreter == null || _labels.isEmpty) {
      _isProcessing = false;
      return;
    }

    try {
      // 1. Extreme Memory Optimization: YUV stream mapping directly onto pre-allocated _inputTensor
      // No extra heavy Dart objects (like img.Image) are created inside this tight loop.
      if (Platform.isAndroid && image.format.group == ImageFormatGroup.yuv420) {
        final int imageWidth = image.width;
        final int imageHeight = image.height;

        final int yRowStride = image.planes[0].bytesPerRow;
        final int uvRowStride = image.planes[1].bytesPerRow;
        final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

        // Calculate a center crop to avoid aspect ratio squashing and match the 1:1 _inputSize
        final int size = math.min(imageWidth, imageHeight);
        final int startX = (imageWidth - size) ~/ 2;
        final int startY = (imageHeight - size) ~/ 2;

        // Nearest-neighbor multiplier mapping the 640 loop cleanly back to the source image
        final double ratio = size / _inputSize;

        for (int y = 0; y < _inputSize; y++) {
          final int srcY = startY + (y * ratio).toInt();
          final int pY0 = srcY * yRowStride;
          final int pUV0 = (srcY ~/ 2) * uvRowStride;

          // Cache current row of the target tensor to avoid list index overhead
          final List<List<double>> outputRow = _inputTensor[0][y];

          for (int x = 0; x < _inputSize; x++) {
            final int srcX = startX + (x * ratio).toInt();

            // Extract raw buffer YUV vectors
            final int yp = image.planes[0].bytes[pY0 + srcX];
            final int uvOffset = pUV0 + (srcX ~/ 2) * uvPixelStride;
            final int up = image.planes[1].bytes[uvOffset];
            final int vp = image.planes[2].bytes[uvOffset];

            // Integer algebra YUV to RGB conversion
            final int c = yp - 16;
            final int d = up - 128;
            final int e = vp - 128;

            int r = (298 * c + 409 * e + 128) >> 8;
            int g = (298 * c - 100 * d - 208 * e + 128) >> 8;
            int b = (298 * c + 516 * d + 128) >> 8;

            // Clamp out-of-boundary RGB overflows
            r = r.clamp(0, 255);
            g = g.clamp(0, 255);
            b = b.clamp(0, 255);

            // Directly write the 0.0 - 1.0 normalized value in-place to pre-allocated tensor
            final List<double> pixel = outputRow[x];
            pixel[0] = r / 255.0; // R
            pixel[1] = g / 255.0; // G
            pixel[2] = b / 255.0; // B
          }
        }
      }

      // 2. Extracted TFLite trigger. Run against globally modified tensor blocks
      _interpreter!.run(_inputTensor, _outputTensor);

      // 3. Parse output and extract bounding boxes
      _recognitions = _parseYolov8Output(_outputTensor[0]);

      if (mounted) {
        setState(() {}); // Repaint bounding boxes
      }
    } catch (e) {
      debugPrint("Inference error: $e");
    } finally {
      // Release lock
      _isProcessing = false;
    }
  }

  double _calculateIoU(Rect a, Rect b) {
    final double intersectionLeft = math.max(a.left, b.left);
    final double intersectionTop = math.max(a.top, b.top);
    final double intersectionRight = math.min(a.right, b.right);
    final double intersectionBottom = math.min(a.bottom, b.bottom);

    if (intersectionRight < intersectionLeft || intersectionBottom < intersectionTop) {
      return 0.0;
    }

    final double intersectionArea = (intersectionRight - intersectionLeft) * (intersectionBottom - intersectionTop);
    final double areaA = a.width * a.height;
    final double areaB = b.width * b.height;

    return intersectionArea / (areaA + areaB - intersectionArea);
  }

  List<Map<String, dynamic>> _parseYolov8Output(List<List<double>> output) {
    List<Map<String, dynamic>> results = [];
    final int numAnchors = 8400; // Expected output tensor length
    final int numClasses = _labels.length;

    double maxFrameConfidence = 0.0;

    // Output parsing logic:
    // output[property][anchor_index]
    // cx, cy, w, h are indices 0, 1, 2, 3. Class scores start at 4.
    for (int i = 0; i < numAnchors; i++) {
      double maxClassProb = 0.0;
      int classIndex = -1;

      // Check all classes for maximum confidence representation on this anchor
      for (int c = 0; c < numClasses; c++) {
        if (4 + c >= output.length) break;

        double prob = output[4 + c][i];
        if (prob > maxClassProb) {
          maxClassProb = prob;
          classIndex = c;
        }
      }

      // Tracking the maximum confidence hit across the entire iteration scope for debug diagnostics
      if (maxClassProb > maxFrameConfidence) maxFrameConfidence = maxClassProb;

      // Only evaluate viable targets
      if (maxClassProb > 0.4) {
        double cx = output[0][i];
        double cy = output[1][i];
        double w = output[2][i];
        double h = output[3][i];

        double xMin, yMin, xMax, yMax;

        // Dynamic Normalization Fix: Check if model output is already normalized
        if (w <= 1.0 && h <= 1.0) {
          xMin = cx - w / 2;
          yMin = cy - h / 2;
          xMax = cx + w / 2;
          yMax = cy + h / 2;
        } else {
          xMin = (cx - w / 2) / _inputSize;
          yMin = (cy - h / 2) / _inputSize;
          xMax = (cx + w / 2) / _inputSize;
          yMax = (cy + h / 2) / _inputSize;
        }

        results.add({
          'rect': Rect.fromLTRB(xMin, yMin, xMax, yMax),
          'confidence': maxClassProb,
          'class': classIndex >= 0 && classIndex < _labels.length
              ? _labels[classIndex]
              : "Unknown",
        });
      }
    }

    // Required Debug Logging hook providing visibility into what the tensor executes
    debugPrint('Highest confidence this frame: $maxFrameConfidence');

    // NMS (Non-Maximum Suppression) Filter
    List<Map<String, dynamic>> nmsResults = [];
    results.sort((a, b) => (b['confidence'] as double).compareTo(a['confidence'] as double));

    for (var res in results) {
      bool keep = true;
      for (var nmsRes in nmsResults) {
        if (res['class'] == nmsRes['class']) { // Per-class NMS
          double iou = _calculateIoU(res['rect'], nmsRes['rect']);
          if (iou > 0.45) { // IoU Threshold
            keep = false;
            break;
          }
        }
      }
      if (keep) nmsResults.add(res);
    }

    return nmsResults;
  }

  @override
  void dispose() {
    _cameraController?.stopImageStream();
    _cameraController?.dispose();
    _interpreter?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vision Test Module')),
      backgroundColor: Colors.black,
      body: _cameraController == null || !_cameraController!.value.isInitialized
          ? const Center(
              child: CircularProgressIndicator(color: Colors.yellowAccent),
            )
          : Stack(
              fit: StackFit.expand,
              children: [
                CameraPreview(_cameraController!),
                SizedBox.expand(
                  child: CustomPaint(painter: BoundingBoxPainter(_recognitions)),
                ),
              ],
            ),
    );
  }
}

class BoundingBoxPainter extends CustomPainter {
  final List<Map<String, dynamic>> recognitions;

  BoundingBoxPainter(this.recognitions);

  @override
  void paint(Canvas canvas, Size size) {
    final boxPaint = Paint()
      ..color = Colors.yellowAccent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;

    for (var rec in recognitions) {
      Rect rect = rec['rect'];
      String label = rec['class'];
      double conf = rec['confidence'];

      // Mathematical 90-degree clockwise rotation for Android portrait CameraImage mapping
      // Original landscape points normalized [0, 1] transposed onto Portrait [0, 1] view
      double rotLeft = 1.0 - rect.bottom;
      double rotTop = rect.left;
      double rotRight = 1.0 - rect.top;
      double rotBottom = rect.right;

      final Rect rotatedRect = Rect.fromLTRB(
        math.min(rotLeft, rotRight),
        math.min(rotTop, rotBottom),
        math.max(rotLeft, rotRight),
        math.max(rotTop, rotBottom),
      );

      // Adapt normalized output parameters back seamlessly onto screen proportions
      final scaledRect = Rect.fromLTRB(
        rotatedRect.left * size.width,
        rotatedRect.top * size.height,
        rotatedRect.right * size.width,
        rotatedRect.bottom * size.height,
      );

      canvas.drawRect(scaledRect, boxPaint);

      final textLabel = '$label ${(conf * 100).toStringAsFixed(1)}%';

      final textPainter = TextPainter(
        text: TextSpan(
          text: textLabel,
          style: const TextStyle(
            color: Colors.black,
            backgroundColor: Colors.yellowAccent,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        textDirection: TextDirection.ltr,
      );

      textPainter.layout();
      textPainter.paint(
        canvas,
        Offset(scaledRect.left, scaledRect.top - textPainter.height),
      );
    }
  }

  @override
  bool shouldRepaint(covariant BoundingBoxPainter oldDelegate) {
    return true;
  }
}
