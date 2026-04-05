import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';

import 'add_maps_screen.dart';
import 'account_screen.dart';
import 'indoor_nav_screen.dart';
import 'outdoor_nav_screen.dart';
import 'vision_test_screen.dart';
import 'sensor_test_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Voice AI Variables
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();
  bool _isListening = false;
  String _spokenText = "";
  String _voiceStatusText = "Hold to speak 'Indoor' or 'Outdoor'";

  @override
  void initState() {
    super.initState();
    _initVoice();
  }

  Future<void> _initVoice() async {
    await _speech.initialize();
    await _flutterTts.awaitSpeakCompletion(true);

    // Greet the user when the app opens!
    await _flutterTts.speak(
      "Welcome to the Navigation App. Hold the bottom button and say Indoor or Outdoor.",
    );
  }

  // --- CONVERSATIONAL VOICE PIPELINE ---
  void _startVoiceCommand() async {
    bool available = await _speech.initialize();
    if (available) {
      setState(() {
        _isListening = true;
        _voiceStatusText = "Listening...";
        _spokenText = ""; // Clear the vault
      });

      bool hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator) Vibration.vibrate(duration: 50);

      _speech.listen(
        onResult: (val) {
          if (val.recognizedWords.trim().isNotEmpty) {
            setState(() {
              _spokenText = val.recognizedWords;
              _voiceStatusText = "Recognized: $_spokenText";
            });
          }
        },
      );
    }
  }

  void _stopVoiceCommand() async {
    setState(() => _isListening = false);
    await _speech.stop();

    // Race condition lock
    if (_spokenText.isEmpty) {
      setState(() => _voiceStatusText = "Processing...");
      await Future.delayed(const Duration(seconds: 1));
    }

    String recognizedWords = _spokenText.toLowerCase().trim();

    setState(() {
      if (recognizedWords.isEmpty) {
        _voiceStatusText = "Failed to hear. Try again.";
      }
    });

    if (recognizedWords.isEmpty) {
      String errorText = "Failed to hear anything. Please try again.";
      if (mounted) {
        SemanticsService.sendAnnouncement(
          View.of(context),
          errorText,
          TextDirection.ltr,
        );
      }
      await _flutterTts.speak(errorText);
      return;
    }

    _processHomeVoiceCommand(recognizedWords);
  }

  Future<void> _processHomeVoiceCommand(String spokenText) async {
    if (spokenText.contains('indoor') || spokenText.contains('in door')) {
      await _flutterTts.speak("Opening Indoor Navigation.");
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const IndoorNavScreen()),
        );
      }
    } else if (spokenText.contains('outdoor') ||
        spokenText.contains('out door')) {
      await _flutterTts.speak("Opening Outdoor Navigation.");
      if (mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const OutdoorNavScreen()),
        );
      }
    } else {
      String errorText =
          "Command not recognized. Please say Indoor or Outdoor.";
      setState(() => _voiceStatusText = "Not recognized");
      if (mounted) {
        SemanticsService.sendAnnouncement(
          View.of(context),
          errorText,
          TextDirection.ltr,
        );
      }
      await _flutterTts.speak(errorText);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black, // High contrast background
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.yellowAccent),
        title: Semantics(
          header: true,
          child: const Text(
            'Home Navigation',
            style: TextStyle(
              color: Colors.yellowAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        actions: [
          Semantics(
            button: true,
            label: 'Add Maps',
            onTapHint: 'Navigate to Add Maps screen',
            child: IconButton(
              icon: const Icon(Icons.map),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AddMapsScreen(),
                  ),
                );
              },
            ),
          ),
          Semantics(
            button: true,
            label: 'Account',
            onTapHint: 'Navigate to Account screen',
            child: IconButton(
              icon: const Icon(Icons.person),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AccountScreen(),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // --- MAIN BUTTONS ---
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: 'Indoor Navigation',
                      onTapHint: 'Start indoor navigation',
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.yellowAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const IndoorNavScreen(),
                            ),
                          );
                        },
                        child: const Text(
                          'Indoor\nNavigation',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Semantics(
                      button: true,
                      label: 'Outdoor Navigation',
                      onTapHint: 'Start outdoor navigation',
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.yellowAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const OutdoorNavScreen(),
                            ),
                          );
                        },
                        child: const Text(
                          'Outdoor\nNavigation',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // --- SUPERVISOR TEST BUTTONS ---
                  Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          button: true,
                          label: 'Vision Test',
                          onTapHint: 'Navigate to real-time vision test screen',
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const VisionTestScreen(),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: const Text(
                              'Vision Test',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Semantics(
                          button: true,
                          label: 'Sensors Test',
                          onTapHint:
                              'Navigate to real-time sensors test screen',
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      const SensorTestScreen(),
                                ),
                              );
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                            ),
                            child: const Text(
                              'Sensor Test',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // --- VOICE COMMAND BOTTOM BAR ---
          Semantics(
            liveRegion: true,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(
                _voiceStatusText,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.yellowAccent,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Semantics(
            button: true,
            label: 'Hold to speak voice command. Say Indoor or Outdoor.',
            child: GestureDetector(
              onLongPress: _startVoiceCommand,
              onLongPressUp: _stopVoiceCommand,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 36.0),
                decoration: BoxDecoration(
                  color: _isListening
                      ? Colors.yellowAccent.withValues(alpha: 0.8)
                      : Colors.yellowAccent,
                  border: const Border(
                    top: BorderSide(color: Colors.yellow, width: 2),
                  ),
                ),
                alignment: Alignment.center,
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.mic, color: Colors.black, size: 56),
                    SizedBox(width: 16),
                    Text(
                      'HOLD TO SPEAK',
                      style: TextStyle(
                        color: Colors.black,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
