import 'dart:async';
import 'dart:developer';
import 'dart:io';
import 'dart:math' as math; // Added for the math.min calculations

import 'package:camera/camera.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:tflite_flutter/tflite_flutter.dart';
import 'package:vibration/vibration.dart';

/// Phase 8: Final Orchestration & Background ML
/// Headless Singleton background service for YOLOv8 object detection
class VisionService {
  // Singleton Pattern
  static final VisionService _instance = VisionService._internal();
  static VisionService get instance => _instance;

  VisionService._internal();

  CameraController? _cameraController;
  Interpreter? _interpreter;
  final FlutterTts _flutterTts = FlutterTts();

  bool _isDetecting = false;
  bool _isProcessingFrame = false;

  // Smart Throttling (Anti-Spam)
  final Map<String, DateTime> _debounceTimer = {};
  final Duration _debounceDuration = const Duration(seconds: 4);

  // Multimodal Constraint: Navigation engine priority
  bool isNavigationSpeaking = false;

  // --- Phase 4 Memory Optimization Variables ---
  final int _inputSize = 640;
  late final List<List<List<List<double>>>> _inputTensor;
  late final List<List<List<double>>> _outputTensor;

  // Standard COCO Labels for YOLOv8 (80 classes)
  final List<String> _labels = [
    'person',
    'bicycle',
    'car',
    'motorcycle',
    'airplane',
    'bus',
    'train',
    'truck',
    'boat',
    'traffic light',
    'fire hydrant',
    'stop sign',
    'parking meter',
    'bench',
    'bird',
    'cat',
    'dog',
    'horse',
    'sheep',
    'cow',
    'elephant',
    'bear',
    'zebra',
    'giraffe',
    'backpack',
    'umbrella',
    'handbag',
    'tie',
    'suitcase',
    'frisbee',
    'skis',
    'snowboard',
    'sports ball',
    'kite',
    'baseball bat',
    'baseball glove',
    'skateboard',
    'surfboard',
    'tennis racket',
    'bottle',
    'wine glass',
    'cup',
    'fork',
    'knife',
    'spoon',
    'bowl',
    'banana',
    'apple',
    'sandwich',
    'orange',
    'broccoli',
    'carrot',
    'hot dog',
    'pizza',
    'donut',
    'cake',
    'chair',
    'couch',
    'potted plant',
    'bed',
    'dining table',
    'toilet',
    'tv',
    'laptop',
    'mouse',
    'remote',
    'keyboard',
    'cell phone',
    'microwave',
    'oven',
    'toaster',
    'sink',
    'refrigerator',
    'book',
    'clock',
    'vase',
    'scissors',
    'teddy bear',
    'hair drier',
    'toothbrush',
  ];

  Future<void> init() async {
    try {
      // 1. Globally pre-allocate the TFLite tensors once to prevent GC thrashing
      _inputTensor = List.generate(
        1,
        (index) => List.generate(
          _inputSize,
          (y) => List.generate(_inputSize, (x) => List.filled(3, 0.0)),
        ),
      );

      _outputTensor = List.generate(
        1,
        (index) => List.generate(84, (i) => List.filled(8400, 0.0)),
      );

      // 2. Initialize Interpreter
      _interpreter = await Interpreter.fromAsset('assets/yolov8n.tflite');

      await _flutterTts.setLanguage("en-US");
      await _flutterTts.setSpeechRate(0.55);
      await _flutterTts.setPitch(1.1); // Slightly distinct pitch for hazards
    } catch (e) {
      log('Error initializing VisionService: $e');
    }
  }

  Future<void> startDetection() async {
    if (_isDetecting) return;

    if (_interpreter == null) {
      await init();
    }

    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        log('No cameras available for VisionService.');
        return;
      }

      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );

      await _cameraController!.initialize();
      _isDetecting = true;

      _cameraController!.startImageStream((CameraImage image) {
        if (_isProcessingFrame) return; // Drop frame if TFLite is busy
        _isProcessingFrame = true;
        _processCameraImage(image);
      });

      log('VisionService started streaming headlessly.');
    } catch (e) {
      log('Error starting image stream in VisionService: $e');
      _isDetecting = false;
    }
  }

  Future<void> stopDetection() async {
    if (!_isDetecting) return;

    try {
      if (_cameraController != null &&
          _cameraController!.value.isStreamingImages) {
        await _cameraController!.stopImageStream();
      }
      await _cameraController?.dispose();
      _cameraController = null;
    } catch (e) {
      log('Error stopping VisionService: $e');
    }

    _isDetecting = false;
    _isProcessingFrame = false;
    log('VisionService stopped detection.');
  }

  void _processCameraImage(CameraImage image) async {
    try {
      if (_interpreter == null) return;

      // 1. Populate the pre-allocated _inputTensor with Phase 4 math
      _populateInputTensor(image);

      // 2. Run Inference using the pre-allocated tensors
      _interpreter!.run(_inputTensor, _outputTensor);

      // 3. Parse output and find objects with confidence > 0.60
      _parseOutput(_outputTensor[0]);
    } catch (e) {
      log('Error predicting frame: $e');
    } finally {
      // Release flag to accept the next frame
      _isProcessingFrame = false;
    }
  }

  void _populateInputTensor(CameraImage image) {
    // Extreme Memory Optimization: YUV stream mapping directly onto pre-allocated _inputTensor
    if (Platform.isAndroid && image.format.group == ImageFormatGroup.yuv420) {
      final int imageWidth = image.width;
      final int imageHeight = image.height;

      final int yRowStride = image.planes[0].bytesPerRow;
      final int uvRowStride = image.planes[1].bytesPerRow;
      final int uvPixelStride = image.planes[1].bytesPerPixel ?? 1;

      final int size = math.min(imageWidth, imageHeight);
      final int startX = (imageWidth - size) ~/ 2;
      final int startY = (imageHeight - size) ~/ 2;
      final double ratio = size / _inputSize;

      for (int y = 0; y < _inputSize; y++) {
        final int srcY = startY + (y * ratio).toInt();
        final int pY0 = srcY * yRowStride;
        final int pUV0 = (srcY ~/ 2) * uvRowStride;

        final List<List<double>> outputRow = _inputTensor[0][y];

        for (int x = 0; x < _inputSize; x++) {
          final int srcX = startX + (x * ratio).toInt();

          final int yp = image.planes[0].bytes[pY0 + srcX];
          final int uvOffset = pUV0 + (srcX ~/ 2) * uvPixelStride;
          final int up = image.planes[1].bytes[uvOffset];
          final int vp = image.planes[2].bytes[uvOffset];

          final int c = yp - 16;
          final int d = up - 128;
          final int e = vp - 128;

          int r = (298 * c + 409 * e + 128) >> 8;
          int g = (298 * c - 100 * d - 208 * e + 128) >> 8;
          int b = (298 * c + 516 * d + 128) >> 8;

          r = r.clamp(0, 255);
          g = g.clamp(0, 255);
          b = b.clamp(0, 255);

          final List<double> pixel = outputRow[x];
          pixel[0] = r / 255.0; // R
          pixel[1] = g / 255.0; // G
          pixel[2] = b / 255.0; // B
        }
      }
    }
  }

  void _parseOutput(List<List<double>> output) {
    const double threshold = 0.60;
    String? detectedHazard;
    double maxConfidence = 0.0;

    // Scan the anchor boxes
    for (int boxIdx = 0; boxIdx < 8400; boxIdx++) {
      for (int classIdx = 0; classIdx < 80; classIdx++) {
        double confidence = output[classIdx + 4][boxIdx];
        if (confidence > threshold && confidence > maxConfidence) {
          maxConfidence = confidence;
          detectedHazard = _labels[classIdx];
        }
      }
    }

    if (detectedHazard != null) {
      _handleHazard(detectedHazard);
    }
  }

  void _handleHazard(String objectName) async {
    final now = DateTime.now();

    // Smart Throttling (Anti-Spam)
    if (_debounceTimer.containsKey(objectName)) {
      final lastTime = _debounceTimer[objectName]!;
      if (now.difference(lastTime) < _debounceDuration) {
        return; // Suppress spam for this specific object
      }
    }

    _debounceTimer[objectName] = now;
    log('Hazard detected: $objectName');

    // Multimodal Priority 1: Haptic distinct rapid vibration
    bool? hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator == true) {
      Vibration.vibrate(pattern: [0, 150, 50, 150, 50, 300]);
    }

    // Multimodal Priority 2: Conditional Speech
    if (isNavigationSpeaking) {
      log('Suppressed hazard TTS because navigation engine is speaking.');
      return;
    }

    await _flutterTts.speak("Caution: $objectName");
  }
}
