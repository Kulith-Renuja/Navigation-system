import 'package:flutter/material.dart';

class AddMapsScreen extends StatelessWidget {
  const AddMapsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Semantics(header: true, child: Text('Add Maps'))),
      body: Center(
        child: Semantics(
          label: 'This is the Add Maps screen placeholder',
          child: const Text('Add Maps Screen'),
        ),
      ),
    );
  }
}
