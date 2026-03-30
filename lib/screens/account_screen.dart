import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final TextEditingController _nameController = TextEditingController();
  bool _isLoading = false;
  String? _uid;

  @override
  void initState() {
    super.initState();
    _handleAuth();
  }

  Future<void> _handleAuth() async {
    try {
      final userCredential = await FirebaseAuth.instance.signInAnonymously();
      if (mounted) {
        setState(() {
          _uid = userCredential.user?.uid;
        });
      }
    } catch (e) {
      debugPrint("Auth Error: $e");
    }
  }

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) return;

    setState(() {
      _isLoading = true;
    });

    try {
      if (_uid == null) {
        await _handleAuth();
      }

      if (_uid != null) {
        await FirebaseFirestore.instance.collection('users').doc(_uid).set({
          'name': name,
        });

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Name saved successfully!',
              style: TextStyle(fontSize: 20, color: Colors.black),
            ),
            backgroundColor: Colors.greenAccent,
            duration: Duration(seconds: 3),
          ),
        );
        SemanticsService.announce('Name saved successfully', TextDirection.ltr);
      } else {
        throw Exception("Could not authenticate user anonymously.");
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Error saving name: $e',
            style: const TextStyle(fontSize: 20, color: Colors.white),
          ),
          backgroundColor: Colors.redAccent,
          duration: const Duration(seconds: 4),
        ),
      );
      SemanticsService.announce('Error saving name', TextDirection.ltr);
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Scaffold is not const because its children are dynamic and have state interactions.
    return Scaffold(
      appBar: AppBar(
        title: const Semantics(header: true, child: Text('Account')),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              label: 'Text field for entering your name',
              textField: true,
              child: TextField(
                controller: _nameController,
                style: const TextStyle(fontSize: 28, color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Your Name',
                  labelStyle: TextStyle(
                    fontSize: 24,
                    color: Colors.yellowAccent,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: Colors.yellowAccent,
                      width: 2,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(
                      color: Colors.yellowAccent,
                      width: 4,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            if (_isLoading)
              const Center(
                child: Semantics(
                  label: 'Loading, please wait while saving your name',
                  child: CircularProgressIndicator(color: Colors.yellowAccent),
                ),
              )
            else
              Semantics(
                button: true,
                label: 'Save Name',
                onTapHint: 'Saves your name to the cloud',
                child: ElevatedButton(
                  onPressed: _saveName,
                  child: const Text('Save Name'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
