import 'package:flutter/material.dart';
import 'add_maps_screen.dart';
import 'account_screen.dart';
import 'indoor_nav_screen.dart';
import 'outdoor_nav_screen.dart';

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
          ],
        ),
      ),
    );
  }
}
