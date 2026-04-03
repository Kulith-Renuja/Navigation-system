import 'package:flutter/material.dart';
import 'add_maps_screen.dart';
import 'account_screen.dart';
import 'indoor_nav_screen.dart';
import 'outdoor_nav_screen.dart';
// 1. Add this import at the top of home_screen.dart
import 'vision_test_screen.dart';
import 'sensor_test_screen.dart';
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Semantics(header: true, child: Text('Home Navigation')),
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
      body: Padding(
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
                  ),
                ),
              ),
            ),
            // 2. Drop this inside your main Column children array:
            const SizedBox(height: 16),
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
                        builder: (context) => const VisionTestScreen(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    // Distinguishable color for our developer test module
                    backgroundColor: Colors.deepPurple,
                  ),
                  child: const Text(
                    'Vision Test\n(Standalone)',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: Semantics(
                button: true,
                label: 'Sensors Test',
                onTapHint: 'Navigate to real-time sensors test screen',
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SensorTestScreen(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                  ),
                  child: const Text(
                    'Sensors & Feedback Test\n(Standalone)',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
