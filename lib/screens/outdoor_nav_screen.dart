import 'package:flutter/material.dart';

class OutdoorNavScreen extends StatelessWidget {
  const OutdoorNavScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Semantics(header: true, child: Text('Outdoor Navigation')),
      ),
      body: Center(
        child: Semantics(
          label: 'This is the Outdoor Navigation screen placeholder',
          child: const Text('Outdoor Navigation Screen'),
        ),
      ),
    );
  }
}
