import 'package:flutter/material.dart';

class IndoorNavScreen extends StatelessWidget {
  const IndoorNavScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Semantics(header: true, child: Text('Indoor Navigation')),
      ),
      body: Center(
        child: Semantics(
          label: 'This is the Indoor Navigation screen placeholder',
          child: const Text('Indoor Navigation Screen'),
        ),
      ),
    );
  }
}
