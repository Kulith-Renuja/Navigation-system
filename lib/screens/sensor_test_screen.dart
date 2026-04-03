import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:pedometer/pedometer.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:permission_handler/permission_handler.dart';

class SensorTestScreen extends StatefulWidget {
  const SensorTestScreen({super.key});

  @override
  State<SensorTestScreen> createState() => _SensorTestScreenState();
}

class _SensorTestScreenState extends State<SensorTestScreen> {
  // TTS State
  final FlutterTts _flutterTts = FlutterTts();
  final TextEditingController _ttsController = TextEditingController(text: "Turn left in 10 steps");

  // Compass State
  StreamSubscription<CompassEvent>? _compassSubscription;
  double? _heading;

  // Pedometer State
  StreamSubscription<StepCount>? _stepCountSubscription;
  String _stepCount = 'Initializing...';

  @override
  void initState() {
    super.initState();
    _initCompass();
    _initPedometer();
  }

  // --- MODULE A: TEXT-TO-SPEECH ---
  Future<void> _speak() async {
    try {
      if (_ttsController.text.isNotEmpty) {
        await _flutterTts.speak(_ttsController.text);
      }
    } catch (e) {
      debugPrint("TTS Error: $e");
    }
  }

  // --- MODULE B: VIBRATION ---
  Future<void> _triggerVibration(String type) async {
    try {
      bool? hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator != true) {
        debugPrint("Device does not support vibration.");
        return;
      }

      switch (type) {
        case 'light':
          // Short, low intensity tap
          Vibration.vibrate(duration: 50, amplitude: 128);
          break;
        case 'directional':
          // Medium pulse
          Vibration.vibrate(pattern: [0, 200, 100, 200]);
          break;
        case 'hazard':
          // Long repeating hazard pattern
          Vibration.vibrate(pattern: [0, 500, 200, 500, 200, 500]);
          break;
      }
    } catch (e) {
      debugPrint("Vibration processing error: $e");
    }
  }

  // --- MODULE C: COMPASS ---
  void _initCompass() {
    try {
      _compassSubscription = FlutterCompass.events?.listen((CompassEvent event) {
        if (mounted) {
          setState(() {
            _heading = event.heading;
          });
        }
      }, onError: (error) {
        debugPrint("Compass Stream error: $error");
      });
    } catch (e) {
      debugPrint("Compass Initialization error: $e");
    }
  }

  String _getCardinalDirection(double? heading) {
    if (heading == null) return "Unknown";
    // Modulo math ensures we loop perfectly inside the 0-360 bound
    double h = heading < 0 ? (heading % 360) + 360 : (heading % 360);
    
    if (h >= 337.5 || h < 22.5) return "N";
    if (h >= 22.5 && h < 67.5) return "NE";
    if (h >= 67.5 && h < 112.5) return "E";
    if (h >= 112.5 && h < 157.5) return "SE";
    if (h >= 157.5 && h < 202.5) return "S";
    if (h >= 202.5 && h < 247.5) return "SW";
    if (h >= 247.5 && h < 292.5) return "W";
    if (h >= 292.5 && h < 337.5) return "NW";
    return "Unknown";
  }

  // --- MODULE D: PEDOMETER ---
  Future<bool> _requestActivityPermission() async {
    PermissionStatus status = await Permission.activityRecognition.request();
    return status.isGranted;
  }

  Future<void> _initPedometer() async {
    try {
      bool isGranted = await _requestActivityPermission();
      if (!isGranted) {
        if (mounted) {
          setState(() {
            _stepCount = 'Permission Denied';
          });
        }
        return; // Halt initialization if the user rejects the prompt
      }

      _stepCountSubscription = Pedometer.stepCountStream.listen(
        (StepCount event) {
          if (mounted) {
            setState(() {
              _stepCount = event.steps.toString();
            });
          }
        },
        onError: (error) {
          if (mounted) {
            setState(() {
              _stepCount = 'Permission Denied / Error: $error';
            });
          }
          debugPrint("Pedometer Stream error: $error");
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _stepCount = 'API Error: $e';
        });
      }
      debugPrint("Pedometer Initialization error: $e");
    }
  }

  @override
  void dispose() {
    // Memory leak prevention block
    _compassSubscription?.cancel();
    _stepCountSubscription?.cancel();
    _ttsController.dispose();
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sensors & Feedback Core'),
        backgroundColor: Colors.black, // High contrast
      ),
      backgroundColor: Colors.grey[900],
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          _buildTTSCard(),
          _buildHapticCard(),
          _buildCompassCard(),
          _buildPedometerCard(),
        ],
      ),
    );
  }

  Widget _buildTTSCard() {
    return Card(
      color: Colors.black,
      shape: RoundedRectangleBorder(side: const BorderSide(color: Colors.yellowAccent, width: 2), borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Module A: Text-to-Speech', style: TextStyle(fontSize: 20, color: Colors.yellowAccent, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _ttsController,
              style: const TextStyle(color: Colors.white, fontSize: 16),
              decoration: const InputDecoration(
                labelText: 'Message to Announce',
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.yellowAccent)),
                focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.yellowAccent, width: 2.0)),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _speak,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.yellowAccent,
                foregroundColor: Colors.black,
              ),
              child: const Text('Speak', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHapticCard() {
    return Card(
      color: Colors.black,
      shape: RoundedRectangleBorder(side: const BorderSide(color: Colors.yellowAccent, width: 2), borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Module B: Haptic Feedback', style: TextStyle(fontSize: 20, color: Colors.yellowAccent, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => _triggerVibration('light'),
              child: const Text('Light Tap', style: TextStyle(color: Colors.yellowAccent)),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => _triggerVibration('directional'),
              child: const Text('Directional Turn', style: TextStyle(color: Colors.yellowAccent)),
            ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () => _triggerVibration('hazard'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red[900]),
              child: const Text('Hazard Warning', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompassCard() {
    return Card(
      color: Colors.black,
      shape: RoundedRectangleBorder(side: const BorderSide(color: Colors.yellowAccent, width: 2), borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text('Module C: Magnetometer', style: TextStyle(fontSize: 20, color: Colors.yellowAccent, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Text(
              _heading != null ? '${_heading!.toStringAsFixed(1)}°' : 'Awaiting sensor...',
              style: const TextStyle(fontSize: 32, color: Colors.white, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _getCardinalDirection(_heading),
              style: const TextStyle(fontSize: 48, color: Colors.yellowAccent, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPedometerCard() {
    return Card(
      color: Colors.black,
      shape: RoundedRectangleBorder(side: const BorderSide(color: Colors.yellowAccent, width: 2), borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text('Module D: Pedometer', style: TextStyle(fontSize: 20, color: Colors.yellowAccent, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            const Icon(Icons.directions_walk, size: 48, color: Colors.white),
            const SizedBox(height: 16),
            Text(
              _stepCount,
              style: const TextStyle(fontSize: 24, color: Colors.yellowAccent, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
