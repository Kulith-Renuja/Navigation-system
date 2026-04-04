import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_polyline_points/flutter_polyline_points.dart';
import 'package:http/http.dart' as http;
import 'package:vibration/vibration.dart';
import 'package:permission_handler/permission_handler.dart';

// 1. IMPORT ADDED HERE
import '../services/vision_service.dart';

const String googleMapsApiKey = "AIzaSyBK35PHUZQptE17QhepcC_m86y7P-uDzTo";

class DirectionInstruction {
  final String htmlInstruction;
  final String plainTextInstruction;
  final LatLng startLocation;
  final LatLng endLocation;

  DirectionInstruction({
    required this.htmlInstruction,
    required this.plainTextInstruction,
    required this.startLocation,
    required this.endLocation,
  });
}

class OutdoorNavScreen extends StatefulWidget {
  const OutdoorNavScreen({super.key});

  @override
  State<OutdoorNavScreen> createState() => _OutdoorNavScreenState();
}

class _OutdoorNavScreenState extends State<OutdoorNavScreen>
    with WidgetsBindingObserver {
  // Controllers
  final Completer<GoogleMapController> _controller = Completer();
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _flutterTts = FlutterTts();

  // Map Data
  final Set<Polyline> _polylines = {};
  final Set<Marker> _markers = {};

  // Voice Input Variables
  bool _isListening = false;
  String _spokenDestination = "";
  String _currentStatusText = "Hold the button to speak your destination.";

  // Navigation Data
  final List<DirectionInstruction> _instructionQueue = [];
  StreamSubscription<Position>? _positionStream;
  Position? _currentPosition;
  bool _isNavigating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _requestPermissions();
    _initSpeech();

    // 2. TTS WAIT OPTION ADDED HERE
    _flutterTts.awaitSpeakCompletion(true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _speech.cancel();
    _positionStream?.cancel();
    _stopObjectDetection();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      // User minimized the app. Pause the AI camera to save battery!
      VisionService.instance.stopDetection();
    } else if (state == AppLifecycleState.resumed) {
      // User opened the app back up. Turn the AI back on if we are navigating!
      if (_isNavigating) {
        VisionService.instance.startDetection();
      }
    }
  }

  // 3. AI START UPDATED HERE
  void _startObjectDetection() async {
    await VisionService.instance.startDetection();
    debugPrint("AI Vision / Object Detection Started.");
  }

  // 4. AI STOP UPDATED HERE
  void _stopObjectDetection() async {
    await VisionService.instance.stopDetection();
    debugPrint("AI Vision / Object Detection Stopped.");
  }

  Future<void> _requestPermissions() async {
    await [Permission.location, Permission.microphone].request();

    if (await Permission.location.isGranted) {
      try {
        _currentPosition = await Geolocator.getCurrentPosition();
        if (mounted) setState(() {});
        if (_currentPosition != null) {
          _moveCamera(_currentPosition!);
        }
      } catch (e) {
        debugPrint("Location initialization error: $e");
      }
    }
  }

  void _initSpeech() async {
    await _speech.initialize();
  }

  Future<void> _moveCamera(Position pos) async {
    final GoogleMapController mapController = await _controller.future;
    mapController.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: LatLng(pos.latitude, pos.longitude), zoom: 17),
      ),
    );
  }

  // --- Voice Input Pipeline ---
  void _startListening() async {
    if (_isNavigating) return;

    if (await Permission.microphone.isGranted) {
      bool hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator) Vibration.vibrate(duration: 100);

      setState(() {
        _isListening = true;
        _currentStatusText = "Listening...";
      });

      _speech.listen(
        onResult: (val) {
          setState(() {
            _spokenDestination = val.recognizedWords;
            _currentStatusText = "Recognized: $_spokenDestination";
          });
        },
        listenFor: const Duration(minutes: 1),
      );
    }
  }

  void _stopListeningAndFetch() async {
    if (_isListening) {
      setState(() {
        _isListening = false;
      });
      await _speech.stop();

      if (_spokenDestination.trim().isNotEmpty) {
        await _flutterTts.speak("Searching for $_spokenDestination.");
        _fetchDirections(_spokenDestination);
      } else {
        String errorText = "Failed to hear destination. Try again.";
        setState(() {
          _currentStatusText = errorText;
        });
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
  }

  String _stripHtml(String htmlString) {
    RegExp exp = RegExp(r"<[^>]*>", multiLine: true, caseSensitive: true);
    return htmlString.replaceAll(exp, '').replaceAll('&nbsp;', ' ').trim();
  }

  // --- Route Fetching & Preparation ---
  Future<void> _fetchDirections(String destination) async {
    setState(() {
      _currentStatusText = "Calculating route to $destination...";
    });
    SemanticsService.sendAnnouncement(
      View.of(context),
      "Calculating route to $destination",
      TextDirection.ltr,
    );
    await _flutterTts.speak("Calculating route to $destination.");

    if (_currentPosition == null) {
      var status = await Permission.location.status;
      if (!status.isGranted) {
        setState(() {
          _currentStatusText = "Location permission required.";
        });
        return;
      }
      _currentPosition = await Geolocator.getCurrentPosition();
    }

    String origin =
        "${_currentPosition!.latitude},${_currentPosition!.longitude}";
    String encodedDest = Uri.encodeComponent(destination);

    String url =
        "https://maps.googleapis.com/maps/api/directions/json?origin=$origin&destination=$encodedDest&mode=walking&key=$googleMapsApiKey";

    try {
      var response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        var data = jsonDecode(response.body);
        if (data['status'] == 'OK') {
          var route = data['routes'][0];
          var leg = route['legs'][0];

          double destLat = leg['end_location']['lat'];
          double destLng = leg['end_location']['lng'];

          _markers.clear();
          _markers.add(
            Marker(
              markerId: const MarkerId('destination'),
              position: LatLng(destLat, destLng),
              infoWindow: InfoWindow(title: destination),
            ),
          );

          String polylineStr = route['overview_polyline']['points'];
          List<PointLatLng> result = PolylinePoints.decodePolyline(polylineStr);

          List<LatLng> polylineCoordinates = [];
          if (result.isNotEmpty) {
            for (var point in result) {
              polylineCoordinates.add(LatLng(point.latitude, point.longitude));
            }
          }

          _polylines.clear();
          _polylines.add(
            Polyline(
              polylineId: const PolylineId('route'),
              color: Colors.green,
              width: 8,
              points: polylineCoordinates,
            ),
          );

          _instructionQueue.clear();
          var steps = leg['steps'];
          for (var step in steps) {
            String html = step['html_instructions'];
            String plain = _stripHtml(html);
            LatLng startLoc = LatLng(
              step['start_location']['lat'],
              step['start_location']['lng'],
            );
            LatLng endLoc = LatLng(
              step['end_location']['lat'],
              step['end_location']['lng'],
            );

            _instructionQueue.add(
              DirectionInstruction(
                htmlInstruction: html,
                plainTextInstruction: plain,
                startLocation: startLoc,
                endLocation: endLoc,
              ),
            );
          }

          setState(() {
            _isNavigating = true;
          });

          _startObjectDetection();
          _startLiveTracking();

          if (_instructionQueue.isNotEmpty) {
            _announceInstruction(_instructionQueue.first.plainTextInstruction);
          }
        } else {
          String errorMsg =
              "Navigation Error. Google Maps could not find a walking route to this destination.";
          setState(() {
            _currentStatusText = errorMsg;
          });
          if (mounted) {
            SemanticsService.sendAnnouncement(
              View.of(context),
              errorMsg,
              TextDirection.ltr,
            );
          }
          _flutterTts.speak(errorMsg);
        }
      } else {
        String errorMsg =
            "Failed to connect to Google Maps. Please check your internet connection.";
        setState(() {
          _currentStatusText = errorMsg;
        });
        if (mounted) {
          SemanticsService.sendAnnouncement(
            View.of(context),
            errorMsg,
            TextDirection.ltr,
          );
        }
        _flutterTts.speak(errorMsg);
      }
    } catch (e) {
      String errorMsg = "Network error. Please try again.";
      setState(() {
        _currentStatusText = errorMsg;
      });
      if (mounted) {
        SemanticsService.sendAnnouncement(
          View.of(context),
          errorMsg,
          TextDirection.ltr,
        );
      }
      _flutterTts.speak(errorMsg);
    }
  }

  // --- Live GPS Tracking ---
  void _startLiveTracking() {
    var locationSettings = AndroidSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 2,
      forceLocationManager: true,
      intervalDuration: const Duration(seconds: 1),
    );

    _positionStream =
        Geolocator.getPositionStream(locationSettings: locationSettings).listen(
          (Position position) {
            if (!mounted) return;
            _currentPosition = position;

            if (_instructionQueue.isNotEmpty) {
              _checkProximity();
            } else {
              _endNavigation(arrived: true);
            }
          },
        );
  }

  void _checkProximity() async {
    if (_instructionQueue.isEmpty) return;

    DirectionInstruction nextStep = _instructionQueue.first;

    double dist = Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      nextStep.endLocation.latitude,
      nextStep.endLocation.longitude,
    );

    if (dist < 15.0) {
      _instructionQueue.removeAt(0);

      bool hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator) Vibration.vibrate(duration: 600, amplitude: 255);

      if (_instructionQueue.isNotEmpty) {
        _announceInstruction(_instructionQueue.first.plainTextInstruction);
      } else {
        _endNavigation(arrived: true);
      }
    }
  }

  // 5. ANNOUNCE INSTRUCTION UPDATED HERE (AI LOCK added)
  void _announceInstruction(String text) async {
    setState(() {
      _currentStatusText = text;
    });
    SemanticsService.sendAnnouncement(
      View.of(context),
      text,
      TextDirection.ltr,
    );

    // Lock the AI voice, speak the routing, then unlock!
    VisionService.instance.isNavigationSpeaking = true;
    await _flutterTts.speak(text);
    VisionService.instance.isNavigationSpeaking = false;
  }

  void _endNavigation({bool arrived = false}) async {
    _positionStream?.cancel();
    _stopObjectDetection();

    if (arrived) {
      setState(() {
        _currentStatusText = "You have arrived at your destination.";
      });
      await _flutterTts.speak("You have arrived at your destination.");
      bool hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator) Vibration.vibrate(pattern: [0, 200, 100, 200, 100, 500]);
    } else {
      setState(() {
        _currentStatusText =
            "Navigation ended. Hold the button to speak your destination.";
      });
      await _flutterTts.speak("Navigation ended.");
    }

    setState(() {
      _isNavigating = false;
      _instructionQueue.clear();
      _polylines.clear();
      _markers.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.yellowAccent),
        title: Semantics(
          header: true,
          child: const Text(
            "Outdoor Navigation",
            style: TextStyle(
              color: Colors.yellowAccent,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          // Top Half: Google Map View
          Expanded(
            flex: 1,
            child: _currentPosition == null
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Colors.yellowAccent,
                    ),
                  )
                : Semantics(
                    label: 'Google Map displaying current location and route',
                    child: GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: LatLng(
                          _currentPosition!.latitude,
                          _currentPosition!.longitude,
                        ),
                        zoom: 16,
                      ),
                      myLocationEnabled: true,
                      myLocationButtonEnabled: true,
                      polylines: _polylines,
                      markers: _markers,
                      onMapCreated: (GoogleMapController controller) {
                        _controller.complete(controller);
                      },
                    ),
                  ),
          ),

          // Bottom Half: Control Panel
          Expanded(
            flex: 1,
            child: Container(
              width: double.infinity,
              color: Colors.black,
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    liveRegion: true,
                    child: Text(
                      _currentStatusText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.yellowAccent,
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),

                  if (!_isNavigating)
                    Semantics(
                      button: true,
                      label: "Hold to Speak Destination Button",
                      child: GestureDetector(
                        onLongPress: _startListening,
                        onLongPressUp: _stopListeningAndFetch,
                        child: Container(
                          decoration: BoxDecoration(
                            color: _isListening
                                ? Colors.yellowAccent.withValues(alpha: 0.5)
                                : Colors.yellowAccent,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.yellowAccent,
                              width: 2,
                            ),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          alignment: Alignment.center,
                          child: const Text(
                            "Hold to Speak",
                            style: TextStyle(
                              color: Colors.black,
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),

                  if (_isNavigating)
                    Semantics(
                      button: true,
                      label: "End Navigation Button",
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        onPressed: () => _endNavigation(arrived: false),
                        child: const Text(
                          "End Navigation",
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: 32,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
