import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'theme/app_theme.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase initialization logic. Make sure google-services.json/GoogleService-Info.plist are added to target platforms.
  try {
    await Firebase.initializeApp();
  } catch (e) {
    debugPrint("Firebase init failed (maybe because no firebaseoptions were provided): $e");
  }
  runApp(const AccessibleNavigationApp());
}

class AccessibleNavigationApp extends StatelessWidget {
  const AccessibleNavigationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Accessible Navigation',
      theme: AppTheme.highContrastTheme,
      home: const HomeScreen(),
    );
  }
}
