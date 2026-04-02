import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/indoor_graph.dart';

class AddMapsScreen extends StatefulWidget {
  const AddMapsScreen({super.key});

  @override
  State<AddMapsScreen> createState() => _AddMapsScreenState();
}

class _AddMapsScreenState extends State<AddMapsScreen> {
  int _currentStep = 0;

  final _locationController = TextEditingController();
  final _buildingController = TextEditingController();
  final _floorController = TextEditingController();

  bool _isGraphBuilderActive = false;
  late IndoorGraph _graph;

  // Form Controls for Start Node
  final _startNodeNameController = TextEditingController();

  // Form Controls for Connections
  String? _selectedNodeId;
  String _selectedDirection = 'forward';
  final _stepCountController = TextEditingController();
  final _newNodeNameController = TextEditingController();

  bool _isUploading = false;

  @override
  void dispose() {
    _locationController.dispose();
    _buildingController.dispose();
    _floorController.dispose();
    _startNodeNameController.dispose();
    _stepCountController.dispose();
    _newNodeNameController.dispose();
    super.dispose();
  }

  void _startMapping() {
    final location = _locationController.text.trim();
    final building = _buildingController.text.trim();
    final floor = _floorController.text.trim();

    if (location.isNotEmpty && building.isNotEmpty && floor.isNotEmpty) {
      setState(() {
        _graph = IndoorGraph(
          locationName: location,
          buildingName: building,
          floorName: floor,
          nodes: [],
          edges: [],
        );
        _isGraphBuilderActive = true;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Please fill out all fields.',
            style: TextStyle(fontSize: 18, color: Colors.white),
          ),
          backgroundColor: Colors.red[800],
        ),
      );
    }
  }

  void _addStartNode() {
    final name = _startNodeNameController.text.trim();
    if (name.isEmpty) return;

    final newNodeId = DateTime.now().millisecondsSinceEpoch.toString();
    final newNode = MapNode(id: newNodeId, name: name, x: 0, y: 0);

    setState(() {
      _graph.nodes.add(newNode);
      _selectedNodeId = newNodeId;
      _startNodeNameController.clear();
    });
  }

  void _addConnection() {
    if (_selectedNodeId == null ||
        _stepCountController.text.isEmpty ||
        _newNodeNameController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please fill all connection fields.'),
          backgroundColor: Colors.red[800],
        ),
      );
      return;
    }

    final fromNode = _graph.nodes.firstWhere((n) => n.id == _selectedNodeId);
    final stepCount = int.tryParse(_stepCountController.text.trim()) ?? 0;

    if (stepCount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Step count must be valid.'),
          backgroundColor: Colors.red[800],
        ),
      );
      return;
    }

    double newX = fromNode.x;
    double newY = fromNode.y;

    if (_selectedDirection == 'forward') {
      newY -= stepCount;
    } else if (_selectedDirection == 'backward') {
      newY += stepCount;
    } else if (_selectedDirection == 'left') {
      newX -= stepCount;
    } else if (_selectedDirection == 'right') {
      newX += stepCount;
    }

    final newNodeId = DateTime.now().millisecondsSinceEpoch.toString();
    final newNodeName = _newNodeNameController.text.trim();

    final newNode = MapNode(id: newNodeId, name: newNodeName, x: newX, y: newY);
    final newEdge = MapEdge(
      fromNodeId: fromNode.id,
      toNodeId: newNodeId,
      direction: _selectedDirection,
      stepCount: stepCount,
    );

    setState(() {
      _graph.nodes.add(newNode);
      _graph.edges.add(newEdge);
      _selectedNodeId = newNodeId;
      _newNodeNameController.clear();
      _stepCountController.clear();
    });
  }

  Future<void> _saveMapToCloud() async {
    if (_graph.nodes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Cannot save an empty map.'),
          backgroundColor: Colors.red[800],
        ),
      );
      return;
    }

    setState(() {
      _isUploading = true;
    });

    try {
      // Bypassing Cloud Storage and saving directly to your free Firestore Database!
      await FirebaseFirestore.instance
          .collection('maps')
          .doc(_graph.locationName)
          .collection(_graph.buildingName)
          .doc(_graph.floorName)
          .set(_graph.toJson());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Map saved to Firestore successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving map: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Avoid const on Scaffold if it has dynamic visual state updates
    return Scaffold(
      appBar: AppBar(title: const Text('Add Maps Builder')),
      body: _isGraphBuilderActive ? _buildGraphBuilder() : _buildStepper(),
    );
  }

  Widget _buildGraphBuilder() {
    return Column(
      children: [
        Expanded(
          flex: 2,
          child: Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: Colors.yellowAccent, width: 2),
              ),
              color: Colors.black, // Dark background canvas
            ),
            child: InteractiveViewer(
              minScale: 0.1,
              maxScale: 10.0,
              child: CustomPaint(
                painter: GraphPainter(_graph),
                child:
                    Container(), // Dummy container to allow layout to size properly
              ),
            ),
          ),
        ),
        Expanded(
          flex: 3,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_graph.nodes.isEmpty)
                  _buildStartNodeForm()
                else
                  _buildConnectNodeForm(),
                const SizedBox(height: 32),
                if (_isUploading)
                  Center(
                    // Avoid const due to state
                    child: CircularProgressIndicator(
                      color: Colors.yellowAccent,
                    ),
                  )
                else
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: Colors.yellowAccent,
                      foregroundColor: Colors.black,
                    ),
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text(
                      'Save Map to Cloud',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: _saveMapToCloud,
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStartNodeForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Add Start Node',
          style: TextStyle(
            fontSize: 20,
            color: Colors.yellowAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _startNodeNameController,
          decoration: const InputDecoration(
            labelText: 'Start Node Name (e.g., Entrance)',
            labelStyle: TextStyle(color: Colors.white54),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.yellowAccent),
            ),
          ),
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _addStartNode,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('Set Start Node', style: TextStyle(fontSize: 16)),
        ),
      ],
    );
  }

  Widget _buildConnectNodeForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Connect New Node',
          style: TextStyle(
            fontSize: 20,
            color: Colors.yellowAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _selectedNodeId,
          decoration: const InputDecoration(
            labelText: 'From Existing Node',
            labelStyle: TextStyle(color: Colors.white54),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.yellowAccent),
            ),
          ),
          dropdownColor: Colors.grey[900],
          style: const TextStyle(color: Colors.yellowAccent, fontSize: 16),
          items: _graph.nodes.map((n) {
            return DropdownMenuItem(value: n.id, child: Text(n.name));
          }).toList(),
          onChanged: (val) {
            setState(() {
              _selectedNodeId = val;
            });
          },
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String>(
          value: _selectedDirection,
          decoration: const InputDecoration(
            labelText: 'Direction',
            labelStyle: TextStyle(color: Colors.white54),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.yellowAccent),
            ),
          ),
          dropdownColor: Colors.grey[900],
          style: const TextStyle(color: Colors.yellowAccent, fontSize: 16),
          items: const [
            DropdownMenuItem(value: 'forward', child: Text('Forward')),
            DropdownMenuItem(value: 'backward', child: Text('Backward')),
            DropdownMenuItem(value: 'left', child: Text('Left')),
            DropdownMenuItem(value: 'right', child: Text('Right')),
          ],
          onChanged: (val) {
            if (val != null) {
              setState(() {
                _selectedDirection = val;
              });
            }
          },
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _stepCountController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Step Count',
            labelStyle: TextStyle(color: Colors.white54),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.yellowAccent),
            ),
          ),
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _newNodeNameController,
          decoration: const InputDecoration(
            labelText: 'New Node Name',
            labelStyle: TextStyle(color: Colors.white54),
            enabledBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: Colors.yellowAccent),
            ),
          ),
          style: const TextStyle(color: Colors.white, fontSize: 18),
        ),
        const SizedBox(height: 24),
        ElevatedButton(
          onPressed: _addConnection,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 16),
            backgroundColor: Colors.grey[850],
          ),
          child: const Text(
            'Add Connection',
            style: TextStyle(color: Colors.yellowAccent, fontSize: 16),
          ),
        ),
      ],
    );
  }

  Widget _buildStepper() {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Colors.yellowAccent,
          secondary: Colors.yellowAccent,
          onSurface: Colors.white,
        ),
      ),
      child: Stepper(
        currentStep: _currentStep,
        onStepContinue: () {
          if (_currentStep < 2) {
            setState(() {
              _currentStep += 1;
            });
          } else {
            _startMapping();
          }
        },
        onStepCancel: () {
          if (_currentStep > 0) {
            setState(() {
              _currentStep -= 1;
            });
          }
        },
        onStepTapped: (step) {
          setState(() {
            _currentStep = step;
          });
        },
        steps: [
          Step(
            title: const Text(
              'Location / Place',
              style: TextStyle(fontSize: 18, color: Colors.yellowAccent),
            ),
            content: TextField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: 'e.g., University of Sri Jayewardenepura',
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.yellowAccent),
                ),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            isActive: _currentStep >= 0,
            state: _currentStep > 0 ? StepState.complete : StepState.indexed,
          ),
          Step(
            title: const Text(
              'Building',
              style: TextStyle(fontSize: 18, color: Colors.yellowAccent),
            ),
            content: TextField(
              controller: _buildingController,
              decoration: const InputDecoration(
                labelText: 'e.g., Faculty of Technology',
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.yellowAccent),
                ),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            isActive: _currentStep >= 1,
            state: _currentStep > 1 ? StepState.complete : StepState.indexed,
          ),
          Step(
            title: const Text(
              'Floor',
              style: TextStyle(fontSize: 18, color: Colors.yellowAccent),
            ),
            content: TextField(
              controller: _floorController,
              decoration: const InputDecoration(
                labelText: 'e.g., Ground Floor',
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.yellowAccent),
                ),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            isActive: _currentStep >= 2,
            state: StepState.indexed,
          ),
        ],
        controlsBuilder: (BuildContext context, ControlsDetails controls) {
          final isLastStep = _currentStep == 2;
          return Padding(
            padding: const EdgeInsets.only(top: 16.0),
            child: Row(
              children: [
                ElevatedButton(
                  onPressed: controls.onStepContinue,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  child: Text(
                    isLastStep ? 'Start Mapping' : 'Continue',
                    style: const TextStyle(fontSize: 18),
                  ),
                ),
                const SizedBox(width: 16),
                if (_currentStep > 0)
                  TextButton(
                    onPressed: controls.onStepCancel,
                    child: const Text(
                      'Back',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class GraphPainter extends CustomPainter {
  final IndoorGraph graph;

  GraphPainter(this.graph);

  @override
  void paint(Canvas canvas, Size size) {
    if (graph.nodes.isEmpty) return;

    // Shift origin to the center of the available space to give nodes room around 0,0
    canvas.translate(size.width / 2, size.height / 2);

    final edgePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final nodePaint = Paint()
      ..color = Colors.yellowAccent
      ..style = PaintingStyle.fill;

    // Scale parameter allows separation of standard step counts to local pixel mapping
    const double scale = 20.0;

    // Draw edges
    for (final edge in graph.edges) {
      try {
        final fromNode = graph.nodes.firstWhere((n) => n.id == edge.fromNodeId);
        final toNode = graph.nodes.firstWhere((n) => n.id == edge.toNodeId);

        final p1 = Offset(fromNode.x * scale, fromNode.y * scale);
        final p2 = Offset(toNode.x * scale, toNode.y * scale);

        canvas.drawLine(p1, p2, edgePaint);

        // Draw the step count in the middle of the line
        final midX = (p1.dx + p2.dx) / 2;
        final midY = (p1.dy + p2.dy) / 2;

        final tp = TextPainter(
          text: TextSpan(
            text: '${edge.stepCount} steps',
            style: const TextStyle(
              color: Colors.black,
              backgroundColor: Colors.yellowAccent,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        );
        tp.layout();
        tp.paint(canvas, Offset(midX - (tp.width / 2), midY - (tp.height / 2)));
      } catch (e) {
        // Ignored node connection error gracefully within UI
      }
    }

    // Draw nodes
    for (final node in graph.nodes) {
      final p = Offset(node.x * scale, node.y * scale);
      canvas.drawCircle(p, 8.0, nodePaint);

      final tp = TextPainter(
        text: TextSpan(
          text: node.name,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, Offset(p.dx + 12, p.dy - (tp.height / 2)));
    }
  }

  @override
  bool shouldRepaint(covariant GraphPainter oldDelegate) {
    return true; // Simplified repaint triggers when visual layout inherently changes
  }
}
