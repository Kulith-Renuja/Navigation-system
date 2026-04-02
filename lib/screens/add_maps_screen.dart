import 'package:flutter/material.dart';

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

  @override
  void dispose() {
    _locationController.dispose();
    _buildingController.dispose();
    _floorController.dispose();
    super.dispose();
  }

  void _startMapping() {
    final location = _locationController.text.trim();
    final building = _buildingController.text.trim();
    final floor = _floorController.text.trim();

    if (location.isNotEmpty && building.isNotEmpty && floor.isNotEmpty) {
      debugPrint('--- Map Metadata ---');
      debugPrint('Location: $location');
      debugPrint('Building: $building');
      debugPrint('Floor: $floor');
      debugPrint('--------------------');

      setState(() {
        _isGraphBuilderActive = true;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Please fill out all fields.',
            style: TextStyle(fontSize: 18, color: Colors.white),
          ),
          backgroundColor: Colors.red[800], // High-contrast red background
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // Avoid const on Scaffold if it has dynamic visual state updates
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Maps Builder'),
      ),
      body: _isGraphBuilderActive ? _buildGraphPlaceholder() : _buildStepper(),
    );
  }

  Widget _buildGraphPlaceholder() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.map, size: 80, color: Colors.yellowAccent),
          SizedBox(height: 20),
          Text(
            'Graph Builder UI goes here',
            style: TextStyle(fontSize: 24, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildStepper() {
    // Using simple Stepper inside Theme to match high-contrast overall look if necessary 
    // This UI is primarily for sighted volunteers 
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
            title: const Text('Location / Place', style: TextStyle(fontSize: 18, color: Colors.yellowAccent)),
            content: TextField(
              controller: _locationController,
              decoration: const InputDecoration(
                labelText: 'e.g., University of Sri Jayewardenepura',
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.yellowAccent)),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            isActive: _currentStep >= 0,
            state: _currentStep > 0 ? StepState.complete : StepState.indexed,
          ),
          Step(
            title: const Text('Building', style: TextStyle(fontSize: 18, color: Colors.yellowAccent)),
            content: TextField(
              controller: _buildingController,
              decoration: const InputDecoration(
                labelText: 'e.g., Faculty of Technology',
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.yellowAccent)),
              ),
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            isActive: _currentStep >= 1,
            state: _currentStep > 1 ? StepState.complete : StepState.indexed,
          ),
          Step(
            title: const Text('Floor', style: TextStyle(fontSize: 18, color: Colors.yellowAccent)),
            content: TextField(
              controller: _floorController,
              decoration: const InputDecoration(
                labelText: 'e.g., Ground Floor',
                labelStyle: TextStyle(color: Colors.white54),
                enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.yellowAccent)),
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
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
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
