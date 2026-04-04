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

import '../models/indoor_graph.dart';

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

class _IndoorNavScreenState extends State<IndoorNavScreen> {
  // Map and Status
  IndoorGraph? _graph;
  bool _isLoading = true;
  String _errorMessage = '';

  MapNode? _startNode;
  MapNode? _destNode;

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
    _checkPermissions();
    _fetchMapData();
  }

  @override
  void dispose() {
    _cleanupSensors();
    super.dispose();
  }

  Future<void> _checkPermissions() async {
    var status = await Permission.activityRecognition.status;
    if (!status.isGranted) {
      await Permission.activityRecognition.request();
    }
  }

  void _cleanupSensors() {
    _stepSubscription?.cancel();
    _stepSubscription = null;
    _compassSubscription?.cancel();
    _compassSubscription = null;
    _hapticTimer?.cancel();
    _hapticTimer = null;
  }

  Future<void> _fetchMapData() async {
    try {
      final docSnapshot = await FirebaseFirestore.instance
          .collection('maps')
          .doc('ueue')
          .collection('mrnr')
          .doc('ekkek')
          .get();

      if (docSnapshot.exists && docSnapshot.data() != null) {
        if (mounted) {
          setState(() {
            _graph = IndoorGraph.fromJson(docSnapshot.data()!);
            _isLoading = false;
          });
          SemanticsService.sendAnnouncement(
            View.of(context),
            'Map loaded',
            TextDirection.ltr,
          );
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'Map data not found.';
          });
          SemanticsService.sendAnnouncement(
            View.of(context),
            'Map data not found.',
            TextDirection.ltr,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Error loading map: $e';
        });
        SemanticsService.sendAnnouncement(
          View.of(context),
          'Error loading map',
          TextDirection.ltr,
        );
      }
      debugPrint("Fetch error: $e");
    }
  }

  // A* Implementation
  List<MapNode> _calculateAStar(
    IndoorGraph graph,
    MapNode start,
    MapNode dest,
  ) {
    if (start.id == dest.id) return [start];

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

      // Bidirectional edge search
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
    return []; // No path found
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

      // Find the edge connecting them
      var edge = _graph!.edges.firstWhere(
        (e) =>
            (e.fromNodeId == curr.id && e.toNodeId == next.id) ||
            (e.fromNodeId == next.id && e.toNodeId == curr.id),
        orElse: () =>
            MapEdge(fromNodeId: '', toNodeId: '', direction: '', stepCount: 0),
      );

      double dx = next.x - curr.x;
      double dy = next.y - curr.y;

      // Negative Y is North, Positive X is East.
      double targetHeading = atan2(dx, -dy) * 180 / pi;
      if (targetHeading < 0) targetHeading += 360;

      steps.add(
        NavStep(
          type: NavStateType.turning,
          instruction: 'Turn towards ${next.name}',
          targetHeading: targetHeading,
          targetNode: next, // Not reaching it yet, but heading there
        ),
      );

      int stepsToWalk = edge.stepCount > 0
          ? edge.stepCount
          : 10; // Fallback if 0

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
      await _flutterTts.speak("You are already at your destination.");
      return;
    }

    List<MapNode> path = _calculateAStar(_graph!, _startNode!, _destNode!);
    if (path.isEmpty) {
      await _flutterTts.speak("No path found to destination.");
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
      await _flutterTts.speak(
        "You are at ${_startNode!.name}. ${_navQueue.first.instruction}.",
      );
    }

    bool hasVibrator = await Vibration.hasVibrator();
    if (hasVibrator) {
      Vibration.vibrate(duration: 500, amplitude: 255);
    }

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
    if (!mounted) return;

    if (_navQueue.isEmpty) {
      await _flutterTts.speak(
        "You have arrived at your destination: ${_destNode!.name}.",
      );
      bool hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator) {
        Vibration.vibrate(pattern: [0, 200, 100, 200, 100, 500]);
      }
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
        _currentHeadingError = 0;
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
      await _flutterTts.speak(
        "You are turned correctly. ${_navQueue.first.instruction}",
      );
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
      await _flutterTts.speak(
        "Arrived at node. ${_navQueue.first.instruction}",
      );
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

  Widget _buildSetupBody() {
    if (_isLoading) {
      return Center(
        child: Semantics(
          label: 'Loading map data, please wait',
          child: const CircularProgressIndicator(
            color: Colors.yellowAccent,
            strokeWidth: 8.0,
          ),
        ),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Semantics(
          label: _errorMessage,
          child: Text(
            _errorMessage,
            style: const TextStyle(
              color: Colors.yellowAccent,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    if (_graph == null || _graph!.nodes.isEmpty) {
      return Center(
        child: Semantics(
          label: 'Map has no nodes available.',
          child: const Text(
            'No Nodes Found',
            style: TextStyle(
              color: Colors.yellowAccent,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Location: ${_graph!.locationName} - ${_graph!.buildingName} Floor ${_graph!.floorName}',
              style: const TextStyle(
                color: Colors.yellowAccent,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 48),
          Semantics(
            label: 'Where are you starting? Dropdown menu.',
            hint: 'Double tap to select your current location',
            child: _buildLargeDropdown(
              value: _startNode,
              hint: 'Where are you starting?',
              onChanged: (MapNode? newValue) {
                setState(() {
                  _startNode = newValue;
                });
                if (newValue != null) {
                  SemanticsService.sendAnnouncement(
                    View.of(context),
                    'Start location set to ${newValue.name}',
                    TextDirection.ltr,
                  );
                }
              },
            ),
          ),
          const SizedBox(height: 32),
          Semantics(
            label: 'Where do you want to go? Dropdown menu.',
            hint: 'Double tap to select your destination',
            child: _buildLargeDropdown(
              value: _destNode,
              hint: 'Where do you want to go?',
              onChanged: (MapNode? newValue) {
                setState(() {
                  _destNode = newValue;
                });
                if (newValue != null) {
                  SemanticsService.sendAnnouncement(
                    View.of(context),
                    'Destination set to ${newValue.name}',
                    TextDirection.ltr,
                  );
                }
              },
            ),
          ),
          const Spacer(),
          Semantics(
            button: true,
            label: 'Calculate Route Button',
            hint: 'Double tap to calculate the route between selected nodes',
            child: ElevatedButton(
              onPressed: (_startNode != null && _destNode != null)
                  ? _startNavigation
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.yellowAccent,
                disabledBackgroundColor: Colors.yellowAccent.withValues(
                  alpha: 0.5,
                ),
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
          ),
          const SizedBox(height: 24),
        ],
      ),
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
        // Top 1/3: Visual Map View
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
        // Middle 1/3: Live Status Area
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
        // Bottom 1/3: Command & Override Area
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
          items: _graph!.nodes.map((MapNode node) {
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
}

class IndoorMapPainter extends CustomPainter {
  final IndoorGraph graph;
  final List<MapNode> pathNodes;
  final MapNode activeNode;

  IndoorMapPainter(this.graph, this.pathNodes, this.activeNode);

  @override
  void paint(Canvas canvas, Size size) {
    if (graph.nodes.isEmpty) return;

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

    // Edges
    var normalEdgePaint = Paint()
      ..color = Colors.yellowAccent
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    for (var edge in graph.edges) {
      try {
        var n1 = graph.nodes.firstWhere((n) => n.id == edge.fromNodeId);
        var n2 = graph.nodes.firstWhere((n) => n.id == edge.toNodeId);
        canvas.drawLine(getOffset(n1), getOffset(n2), normalEdgePaint);
      } catch (_) {
        // Ignore edges pointing to missing nodes safely
      }
    }

    // Path Edges
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

    // Nodes
    var normalNodePaint = Paint()..color = Colors.yellowAccent;
    for (var n in graph.nodes) {
      canvas.drawCircle(getOffset(n), 6.0, normalNodePaint);
    }

    // Active User Node
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
