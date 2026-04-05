import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:vibration/vibration.dart';
import 'package:flutter_compass/flutter_compass.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../models/indoor_graph.dart';
import '../services/vision_service.dart';

enum NavStateType { walking, turning }

class NavStep {
  final NavStateType type;
  final String instruction;
  final int? targetSteps;
  final double? targetHeading;
  final MapNode targetNode;

  NavStep({
    required this.type,
    required this.instruction,
    this.targetSteps,
    this.targetHeading,
    required this.targetNode,
  });
}

class IndoorNavScreen extends StatefulWidget {
  const IndoorNavScreen({super.key});

  @override
  State<IndoorNavScreen> createState() => _IndoorNavScreenState();
}

class _IndoorNavScreenState extends State<IndoorNavScreen>
    with WidgetsBindingObserver {
  // Map and Status
  IndoorGraph? _graph;
  bool _isLoading = false;
  String _errorMessage = '';

  // --- MAP SELECTION STATE ---
  bool _isMapSelected = false;
  String? _selectedPlace;
  String? _selectedBuilding;
  String? _selectedFloor;

  List<String> _availablePlaces = [];
  List<String> _availableBuildings = [];
  List<String> _availableFloors = [];

  // Nodes
  MapNode? _startNode;
  MapNode? _destNode;

  // Voice AI
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _isListening = false;
  String _voiceStatusText = "Hold the button to speak"; // NEW: Visual feedback!
  String _spokenText = ""; // Secure memory for what you said

  // Navigation State
  bool _isNavigating = false;
  List<MapNode> _pathNodes = [];
  Queue<NavStep> _navQueue = Queue();
  NavStep? _currentStep;
  MapNode? _activeNodeTracker;
  bool _isTransitioning = false;

  // Sensors & Subscriptions
  final FlutterTts _flutterTts = FlutterTts();
  StreamSubscription<StepCount>? _stepSubscription;
  StreamSubscription<CompassEvent>? _compassSubscription;
  Timer? _hapticTimer;

  // Tracking Progress
  int? _initialStepCount;
  int _stepsTaken = 0;
  double _currentHeadingError = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
    _initSpeech();
    _fetchAvailablePlaces();

    _flutterTts.awaitSpeakCompletion(true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    VisionService.instance.stopDetection();
    _cleanupSensors();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused) {
      VisionService.instance.stopDetection();
    } else if (state == AppLifecycleState.resumed) {
      if (_isNavigating) {
        VisionService.instance.startDetection();
      }
    }
  }

  void _initSpeech() async {
    await _speech.initialize();
  }

  Future<void> _checkPermissions() async {
    var status = await Permission.activityRecognition.status;
    if (!status.isGranted) {
      await Permission.activityRecognition.request();
    }
    await Permission.microphone.request();
  }

  void _cleanupSensors() {
    _stepSubscription?.cancel();
    _stepSubscription = null;
    _compassSubscription?.cancel();
    _compassSubscription = null;
    _hapticTimer?.cancel();
    _hapticTimer = null;
  }

  // --- DYNAMIC FIREBASE FETCHING ---
  Future<void> _fetchAvailablePlaces() async {
    try {
      var snapshot = await FirebaseFirestore.instance.collection('maps').get();
      setState(() {
        _availablePlaces = snapshot.docs.map((doc) => doc.id).toList();
      });
      VisionService.instance.isNavigationSpeaking = true;
      await _flutterTts.speak(
        "Please hold the screen to speak your place, or select from the dropdown.",
      );
      VisionService.instance.isNavigationSpeaking = false;
    } catch (e) {
      debugPrint("Error fetching places: $e");
    }
  }

  Future<void> _fetchAvailableBuildings(String place) async {
    try {
      var docSnapshot = await FirebaseFirestore.instance
          .collection('maps')
          .doc(place)
          .get();
      if (docSnapshot.exists && docSnapshot.data() != null) {
        List<dynamic> buildings = docSnapshot.data()!['buildings'] ?? [];
        setState(() {
          _availableBuildings = buildings.map((b) => b.toString()).toList();
        });
      }
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> _fetchAvailableFloors(String place, String building) async {
    try {
      var snapshot = await FirebaseFirestore.instance
          .collection('maps')
          .doc(place)
          .collection(building)
          .get();
      setState(() {
        _availableFloors = snapshot.docs.map((doc) => doc.id).toList();
      });
    } catch (e) {
      debugPrint(e.toString());
    }
  }

  Future<void> _fetchMapData() async {
    if (_selectedPlace == null ||
        _selectedBuilding == null ||
        _selectedFloor == null) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      final docSnapshot = await FirebaseFirestore.instance
          .collection('maps')
          .doc(_selectedPlace)
          .collection(_selectedBuilding!)
          .doc(_selectedFloor)
          .get();

      if (docSnapshot.exists && docSnapshot.data() != null) {
        if (mounted) {
          setState(() {
            _graph = IndoorGraph.fromJson(docSnapshot.data()!);
            _isLoading = false;
            _isMapSelected = true;
          });

          VisionService.instance.isNavigationSpeaking = true;
          await _flutterTts.speak(
            'Map loaded. Please hold to speak your start point, or select it from the menu.',
          );
          VisionService.instance.isNavigationSpeaking = false;
        }
      } else {
        if (mounted) setState(() => _errorMessage = 'Map data not found.');
      }
    } catch (e) {
      if (mounted) setState(() => _errorMessage = 'Error loading map: $e');
    }
  }

  // --- UPGRADED CONVERSATIONAL VOICE PIPELINE ---
  void _startVoiceCommand() async {
    bool available = await _speech.initialize();
    if (available) {
      setState(() {
        _isListening = true;
        _voiceStatusText = "Listening...";
        _spokenText = ""; // Clear the vault when you start talking
      });

      bool hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator) Vibration.vibrate(duration: 50);

      _speech.listen(
        onResult: (val) {
          // VAULT LOCK: Only save the word if it is NOT empty!
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

    // THE FIX: If the memory is empty when they let go, wait 1 second for Google to catch up!
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

    // If it heard absolutely nothing after waiting
    if (recognizedWords.isEmpty) {
      VisionService.instance.isNavigationSpeaking = true;
      String errorText =
          "Failed to hear anything. Please hold the button and try again.";
      if (mounted) {
        SemanticsService.sendAnnouncement(
          View.of(context),
          errorText,
          TextDirection.ltr,
        );
      }
      await _flutterTts.speak(errorText);
      VisionService.instance.isNavigationSpeaking = false;
      return;
    }

    _processMapVoiceCommand(recognizedWords);
  }

  Future<void> _processMapVoiceCommand(String spokenText) async {
    VisionService.instance.isNavigationSpeaking = true;

    if (!_isMapSelected) {
      // Phase 1: Map Hierarchy Initialization
      if (_selectedPlace == null) {
        String? match = _fuzzyMatch(spokenText, _availablePlaces);
        if (match != null) {
          setState(() => _selectedPlace = match);
          await _flutterTts.speak(
            "Selected $match place. Now, hold to speak the building.",
          );
          _fetchAvailableBuildings(match);
        } else {
          await _flutterTts.speak(
            "Could not find a place matching $spokenText. Try again.",
          );
        }
      } else if (_selectedBuilding == null) {
        String? match = _fuzzyMatch(spokenText, _availableBuildings);
        if (match != null) {
          setState(() => _selectedBuilding = match);
          await _flutterTts.speak(
            "Selected $match building. Now, hold to speak the floor.",
          );
          _fetchAvailableFloors(_selectedPlace!, match);
        } else {
          await _flutterTts.speak(
            "Could not find a building matching $spokenText. Try again.",
          );
        }
      } else if (_selectedFloor == null) {
        String? match = _fuzzyMatch(spokenText, _availableFloors);
        if (match != null) {
          setState(() => _selectedFloor = match);
          await _flutterTts.speak("Selected $match floor. Loading map.");
          _fetchMapData();
        } else {
          await _flutterTts.speak(
            "Could not find a floor matching $spokenText. Try again.",
          );
        }
      }
    } else {
      // Phase 2: Graph Node Selection
      if (_startNode == null) {
        var match = _fuzzyMatchNode(spokenText);
        if (match != null) {
          setState(() => _startNode = match);
          await _flutterTts.speak(
            "Selected ${match.name} as start point. Now hold to speak your destination.",
          );
        } else {
          await _flutterTts.speak(
            "Could not find a start point matching $spokenText. Try again.",
          );
        }
      } else if (_destNode == null) {
        var match = _fuzzyMatchNode(spokenText);
        if (match != null) {
          setState(() => _destNode = match);
          await _flutterTts.speak(
            "Selected ${match.name} as destination. Route is ready. Say begin or press calculate.",
          );
        } else {
          await _flutterTts.speak(
            "Could not find a destination matching $spokenText. Try again.",
          );
        }
      } else if (spokenText.contains('calculate') ||
          spokenText.contains('start') ||
          spokenText.contains('begin')) {
        _startNavigation();
      }
    }

    VisionService.instance.isNavigationSpeaking = false;
  }

  String? _fuzzyMatch(String spoken, List<String> options) {
    for (var opt in options) {
      if (opt.toLowerCase().contains(spoken) ||
          spoken.contains(opt.toLowerCase())) {
        return opt;
      }
    }
    return null;
  }

  MapNode? _fuzzyMatchNode(String spoken) {
    if (_graph == null) return null;
    for (var node in _graph!.nodes) {
      if (node.name.toLowerCase().contains(spoken) ||
          spoken.contains(node.name.toLowerCase())) {
        return node;
      }
    }
    return null;
  }

  // --- A* IMPLEMENTATION & NAVIGATION LOGIC ---
  List<MapNode> _calculateAStar(
    IndoorGraph graph,
    MapNode start,
    MapNode dest,
  ) {
    if (start.id == dest.id) {
      return [start];
    }

    Set<String> closedSet = {};
    Map<String, double> gScore = {start.id: 0};
    Map<String, double> fScore = {start.id: _heuristic(start, dest)};
    Map<String, String> cameFrom = {};

    List<MapNode> openSet = [start];

    while (openSet.isNotEmpty) {
      openSet.sort(
        (a, b) => (fScore[a.id] ?? double.infinity).compareTo(
          fScore[b.id] ?? double.infinity,
        ),
      );
      var current = openSet.removeAt(0);

      if (current.id == dest.id) {
        return _reconstructPath(cameFrom, current, graph);
      }

      closedSet.add(current.id);

      var neighbors = graph.edges
          .where((e) => e.fromNodeId == current.id || e.toNodeId == current.id)
          .toList();

      for (var edge in neighbors) {
        String neighborId = edge.fromNodeId == current.id
            ? edge.toNodeId
            : edge.fromNodeId;
        if (closedSet.contains(neighborId)) continue;

        double tentativeGScore =
            (gScore[current.id] ?? double.infinity) + edge.stepCount;

        if (tentativeGScore < (gScore[neighborId] ?? double.infinity)) {
          cameFrom[neighborId] = current.id;
          gScore[neighborId] = tentativeGScore;
          var neighborNode = graph.nodes.firstWhere((n) => n.id == neighborId);
          fScore[neighborId] = tentativeGScore + _heuristic(neighborNode, dest);

          if (!openSet.any((n) => n.id == neighborNode.id)) {
            openSet.add(neighborNode);
          }
        }
      }
    }
    return [];
  }

  double _heuristic(MapNode a, MapNode b) {
    return sqrt(pow(a.x - b.x, 2) + pow(a.y - b.y, 2));
  }

  List<MapNode> _reconstructPath(
    Map<String, String> cameFrom,
    MapNode current,
    IndoorGraph graph,
  ) {
    List<String> pathIds = [current.id];
    String currId = current.id;
    while (cameFrom.containsKey(currId)) {
      currId = cameFrom[currId]!;
      pathIds.insert(0, currId);
    }
    return pathIds
        .map((id) => graph.nodes.firstWhere((n) => n.id == id))
        .toList();
  }

  Queue<NavStep> _generateNavSteps(List<MapNode> route) {
    Queue<NavStep> steps = Queue();
    if (route.isEmpty) return steps;

    for (int i = 0; i < route.length - 1; i++) {
      var curr = route[i];
      var next = route[i + 1];

      var edge = _graph!.edges.firstWhere(
        (e) =>
            (e.fromNodeId == curr.id && e.toNodeId == next.id) ||
            (e.fromNodeId == next.id && e.toNodeId == curr.id),
        orElse: () =>
            MapEdge(fromNodeId: '', toNodeId: '', direction: '', stepCount: 0),
      );

      double dx = next.x - curr.x;
      double dy = next.y - curr.y;

      double targetHeading = atan2(dx, -dy) * 180 / pi;
      if (targetHeading < 0) targetHeading += 360;

      steps.add(
        NavStep(
          type: NavStateType.turning,
          instruction: 'Turn towards ${next.name}',
          targetHeading: targetHeading,
          targetNode: next,
        ),
      );

      int stepsToWalk = edge.stepCount > 0 ? edge.stepCount : 10;

      steps.add(
        NavStep(
          type: NavStateType.walking,
          instruction: 'Walk $stepsToWalk steps to ${next.name}',
          targetSteps: stepsToWalk,
          targetNode: next,
        ),
      );
    }
    return steps;
  }

  void _startNavigation() async {
    if (_startNode == null || _destNode == null) return;

    var status = await Permission.activityRecognition.status;
    if (!status.isGranted) {
      status = await Permission.activityRecognition.request();
      if (!status.isGranted) {
        if (mounted) {
          SemanticsService.sendAnnouncement(
            View.of(context),
            "Activity recognition permission refused.",
            TextDirection.ltr,
          );
        }
        return;
      }
    }

    if (_startNode!.id == _destNode!.id) {
      VisionService.instance.isNavigationSpeaking = true;
      await _flutterTts.speak("You are already at your destination.");
      VisionService.instance.isNavigationSpeaking = false;
      return;
    }

    List<MapNode> path = _calculateAStar(_graph!, _startNode!, _destNode!);
    if (path.isEmpty) {
      VisionService.instance.isNavigationSpeaking = true;
      await _flutterTts.speak("No path found to destination.");
      VisionService.instance.isNavigationSpeaking = false;
      return;
    }

    _setupSensors();

    setState(() {
      _pathNodes = path;
      _navQueue = _generateNavSteps(path);
      _activeNodeTracker = _startNode;
      _isNavigating = true;
    });

    if (_navQueue.isNotEmpty) {
      VisionService.instance.isNavigationSpeaking = true;
      await _flutterTts.speak(
        "You are at ${_startNode!.name}. ${_navQueue.first.instruction}.",
      );
      VisionService.instance.isNavigationSpeaking = false;
    }

    bool hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator) {
      Vibration.vibrate(duration: 500, amplitude: 255);
    }

    await VisionService.instance.startDetection();
    _processNextStep();
  }

  void _setupSensors() {
    _stepSubscription = Pedometer.stepCountStream.listen((event) {
      if (!mounted ||
          _isTransitioning ||
          _currentStep?.type != NavStateType.walking) {
        return;
      }

      _initialStepCount ??= event.steps;
      int delta = event.steps - _initialStepCount!;
      setState(() {
        _stepsTaken = delta;
      });

      if (_stepsTaken >= _currentStep!.targetSteps!) {
        _completeWalkingStep();
      }
    });

    _compassSubscription = FlutterCompass.events!.listen((event) {
      if (!mounted ||
          _isTransitioning ||
          _currentStep?.type != NavStateType.turning) {
        return;
      }

      double heading = event.heading ?? 0;
      double target = _currentStep!.targetHeading ?? 0;
      double diff = (target - heading).abs() % 360;
      if (diff > 180) diff = 360 - diff;

      setState(() {
        _currentHeadingError = diff;
      });
    });
  }

  void _processNextStep() async {
    if (!mounted) {
      return;
    }

    if (_navQueue.isEmpty) {
      VisionService.instance.isNavigationSpeaking = true;
      await _flutterTts.speak(
        "You have arrived at your destination: ${_destNode!.name}.",
      );
      VisionService.instance.isNavigationSpeaking = false;

      bool hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator) {
        Vibration.vibrate(pattern: [0, 200, 100, 200, 100, 500]);
      }

      await VisionService.instance.stopDetection();
      _cleanupSensors();

      if (mounted) {
        setState(() {
          _isNavigating = false;
          _startNode = null;
          _destNode = null;
          _pathNodes = [];
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _currentStep = _navQueue.removeFirst();
        _initialStepCount = null;
        _stepsTaken = 0;
        _currentHeadingError = 999.0;
        _isTransitioning = false;
      });
    }

    if (_currentStep!.type == NavStateType.turning) {
      _startTurningState();
    }
  }

  void _startTurningState() {
    _hapticTimer?.cancel();
    _hapticTimer = Timer.periodic(const Duration(milliseconds: 500), (
      timer,
    ) async {
      if (!mounted ||
          _isTransitioning ||
          _currentStep?.type != NavStateType.turning) {
        timer.cancel();
        return;
      }

      if (_currentHeadingError > 10) {
        bool hasVibrator = await Vibration.hasVibrator();
        if (hasVibrator) {
          Vibration.vibrate(duration: 100, amplitude: 100);
        }
      } else {
        _completeTurningStep();
      }
    });
  }

  void _completeTurningStep() async {
    if (_isTransitioning) return;
    _isTransitioning = true;
    _hapticTimer?.cancel();

    if (_navQueue.isNotEmpty) {
      VisionService.instance.isNavigationSpeaking = true;
      await _flutterTts.speak(
        "You are turned correctly. ${_navQueue.first.instruction}",
      );
      VisionService.instance.isNavigationSpeaking = false;
    }
    _processNextStep();
  }

  void _completeWalkingStep() async {
    if (_isTransitioning) return;
    _isTransitioning = true;

    bool hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator) {
      Vibration.vibrate(duration: 600, amplitude: 255);
    }

    if (mounted) {
      setState(() {
        _activeNodeTracker = _currentStep!.targetNode;
      });
    }

    if (_navQueue.isNotEmpty) {
      VisionService.instance.isNavigationSpeaking = true;
      await _flutterTts.speak(
        "Arrived at node. ${_navQueue.first.instruction}",
      );
      VisionService.instance.isNavigationSpeaking = false;
    }

    _processNextStep();
  }

  void _manualOverride() {
    if (_currentStep == null || _isTransitioning) return;
    if (_currentStep!.type == NavStateType.walking) {
      _completeWalkingStep();
    } else {
      _completeTurningStep();
    }
  }

  // --- UI WIDGETS ---
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Semantics(
          header: true,
          child: const Text(
            'Indoor Navigation',
            style: TextStyle(
              color: Colors.yellowAccent,
              fontWeight: FontWeight.bold,
              fontSize: 24,
            ),
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.yellowAccent),
      ),
      body: _isNavigating ? _buildNavigationDashboard() : _buildSetupBody(),
    );
  }

  Widget _buildStringDropdown({
    required String? value,
    required String hint,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: Colors.yellowAccent, width: 4),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(value) ? value : null,
          hint: Text(
            hint,
            style: const TextStyle(
              color: Colors.yellowAccent,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          icon: const Icon(
            Icons.arrow_drop_down,
            color: Colors.yellowAccent,
            size: 48,
          ),
          dropdownColor: Colors.black,
          isExpanded: true,
          style: const TextStyle(
            color: Colors.yellowAccent,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
          items: items
              .map((val) => DropdownMenuItem(value: val, child: Text(val)))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildLargeDropdown({
    required MapNode? value,
    required String hint,
    required ValueChanged<MapNode?> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: Colors.yellowAccent, width: 4),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<MapNode>(
          value: value,
          hint: Text(
            hint,
            style: const TextStyle(
              color: Colors.yellowAccent,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          icon: const Icon(
            Icons.arrow_drop_down,
            color: Colors.yellowAccent,
            size: 48,
          ),
          dropdownColor: Colors.black,
          isExpanded: true,
          style: const TextStyle(
            color: Colors.yellowAccent,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
          items: _graph == null
              ? []
              : _graph!.nodes.map((MapNode node) {
                  return DropdownMenuItem<MapNode>(
                    value: node,
                    child: Text(node.name),
                  );
                }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildSetupBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Colors.yellowAccent,
          strokeWidth: 8,
        ),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Text(
          _errorMessage,
          style: const TextStyle(
            color: Colors.yellowAccent,
            fontSize: 24,
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: _isMapSelected
                ? _buildNodeSelectionUI()
                : _buildMapSelectionUI(),
          ),
        ),
        _buildHoldToSpeakButton(),
      ],
    );
  }

  Widget _buildMapSelectionUI() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "Select Map Setup",
            style: TextStyle(
              color: Colors.yellowAccent,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          _buildStringDropdown(
            value: _selectedPlace,
            hint: 'Select Place',
            items: _availablePlaces,
            onChanged: (val) {
              setState(() => _selectedPlace = val);
              if (val != null) _fetchAvailableBuildings(val);
            },
          ),
          const SizedBox(height: 16),
          _buildStringDropdown(
            value: _selectedBuilding,
            hint: 'Select Building',
            items: _availableBuildings,
            onChanged: (val) {
              setState(() => _selectedBuilding = val);
              if (val != null && _selectedPlace != null) {
                _fetchAvailableFloors(_selectedPlace!, val);
              }
            },
          ),
          const SizedBox(height: 16),
          _buildStringDropdown(
            value: _selectedFloor,
            hint: 'Select Floor',
            items: _availableFloors,
            onChanged: (val) => setState(() => _selectedFloor = val),
          ),
          const SizedBox(height: 32),
          ElevatedButton(
            onPressed:
                (_selectedPlace != null &&
                    _selectedBuilding != null &&
                    _selectedFloor != null)
                ? _fetchMapData
                : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.yellowAccent,
              disabledBackgroundColor: Colors.yellowAccent.withValues(
                alpha: 0.5,
              ),
              padding: const EdgeInsets.symmetric(vertical: 20),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: const Text(
              'Load Map',
              style: TextStyle(
                color: Colors.black,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNodeSelectionUI() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_graph != null)
          Text(
            'Location: ${_graph!.locationName} - Floor ${_graph!.floorName}',
            style: const TextStyle(
              color: Colors.yellowAccent,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: 32),
        _buildLargeDropdown(
          value: _startNode,
          hint: 'Where are you starting?',
          onChanged: (val) => setState(() => _startNode = val),
        ),
        const SizedBox(height: 24),
        _buildLargeDropdown(
          value: _destNode,
          hint: 'Where do you want to go?',
          onChanged: (val) => setState(() => _destNode = val),
        ),
        const Spacer(),
        ElevatedButton(
          onPressed: (_startNode != null && _destNode != null)
              ? _startNavigation
              : null,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.yellowAccent,
            disabledBackgroundColor: Colors.yellowAccent.withValues(alpha: 0.5),
            padding: const EdgeInsets.symmetric(vertical: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          child: const Text(
            'Calculate Route',
            style: TextStyle(
              color: Colors.black,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHoldToSpeakButton() {
    return Column(
      children: [
        // NEW: Visual status text directly above the button, like Outdoor
        Semantics(
          liveRegion: true,
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
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
          label: 'Hold to speak voice command',
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
    );
  }

  Widget _buildNavigationDashboard() {
    String statusText = "Calculating...";
    if (_currentStep != null) {
      if (_currentStep!.type == NavStateType.walking) {
        int remaining = (_currentStep!.targetSteps ?? 0) - _stepsTaken;
        if (remaining < 0) remaining = 0;
        statusText = "$remaining Steps Remaining";
      } else if (_currentStep!.type == NavStateType.turning) {
        statusText = "Turn ${_currentHeadingError.toStringAsFixed(0)}°";
      }
    }

    return Column(
      children: [
        Expanded(
          flex: 1,
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.yellowAccent, width: 2),
              ),
            ),
            child: Semantics(
              label: 'Visual map view showing path',
              child: CustomPaint(
                painter: IndoorMapPainter(
                  _graph!,
                  _pathNodes,
                  _activeNodeTracker!,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          flex: 1,
          child: Container(
            color: Colors.black,
            alignment: Alignment.center,
            child: Semantics(
              liveRegion: true,
              child: Text(
                statusText,
                style: const TextStyle(
                  color: Colors.yellowAccent,
                  fontSize: 48,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        Expanded(
          flex: 1,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            child: Semantics(
              button: true,
              label:
                  'Manual Override Button. Double tap to force next step if sensor fails.',
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.yellowAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: _manualOverride,
                child: Text(
                  _currentStep?.instruction ?? 'Loading...',
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class IndoorMapPainter extends CustomPainter {
  final IndoorGraph graph;
  final List<MapNode> pathNodes;
  final MapNode activeNode;

  IndoorMapPainter(this.graph, this.pathNodes, this.activeNode);

  @override
  void paint(Canvas canvas, Size size) {
    if (graph.nodes.isEmpty) {
      return;
    }

    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;

    for (var n in graph.nodes) {
      if (n.x < minX) minX = n.x;
      if (n.x > maxX) maxX = n.x;
      if (n.y < minY) minY = n.y;
      if (n.y > maxY) maxY = n.y;
    }

    double pad = 20.0;
    double widthMap = maxX - minX;
    double heightMap = maxY - minY;

    if (widthMap == 0) widthMap = 1;
    if (heightMap == 0) heightMap = 1;

    double availableWidth = size.width - pad * 2;
    double availableHeight = size.height - pad * 2;
    if (availableWidth <= 0) availableWidth = 1;
    if (availableHeight <= 0) availableHeight = 1;

    double scaleX = availableWidth / widthMap;
    double scaleY = availableHeight / heightMap;
    double scale = min(scaleX, scaleY);

    double offsetX = (size.width - widthMap * scale) / 2 - minX * scale;
    double offsetY = (size.height - heightMap * scale) / 2 - minY * scale;

    Offset getOffset(MapNode n) {
      return Offset(n.x * scale + offsetX, n.y * scale + offsetY);
    }

    var normalEdgePaint = Paint()
      ..color = Colors.yellowAccent
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    for (var edge in graph.edges) {
      try {
        var n1 = graph.nodes.firstWhere((n) => n.id == edge.fromNodeId);
        var n2 = graph.nodes.firstWhere((n) => n.id == edge.toNodeId);
        canvas.drawLine(getOffset(n1), getOffset(n2), normalEdgePaint);
      } catch (_) {}
    }

    var pathEdgePaint = Paint()
      ..color = Colors.green
      ..strokeWidth = 6.0
      ..style = PaintingStyle.stroke;

    for (int i = 0; i < pathNodes.length - 1; i++) {
      canvas.drawLine(
        getOffset(pathNodes[i]),
        getOffset(pathNodes[i + 1]),
        pathEdgePaint,
      );
    }

    var normalNodePaint = Paint()..color = Colors.yellowAccent;
    for (var n in graph.nodes) {
      canvas.drawCircle(getOffset(n), 6.0, normalNodePaint);
    }

    var activeNodePaint = Paint()..color = Colors.green;
    canvas.drawCircle(getOffset(activeNode), 12.0, activeNodePaint);
  }

  @override
  bool shouldRepaint(covariant IndoorMapPainter oldDelegate) {
    return oldDelegate.pathNodes != pathNodes ||
        oldDelegate.activeNode != activeNode ||
        oldDelegate.graph != graph;
  }
}
