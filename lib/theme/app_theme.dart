import 'package:flutter/material.dart';

class AppTheme {
  static ThemeData get highContrastTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: Colors.yellowAccent,
      scaffoldBackgroundColor: Colors.black,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.black,
        foregroundColor: Colors.yellowAccent,
        iconTheme: IconThemeData(color: Colors.yellowAccent, size: 36),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.yellowAccent,
          foregroundColor: Colors.black,
          textStyle: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
          padding: const EdgeInsets.all(24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: Colors.yellowAccent,
          iconSize: 36,
        ),
      ),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: Colors.white, fontSize: 24),
        bodyMedium: TextStyle(color: Colors.white, fontSize: 20),
        titleLarge: TextStyle(color: Colors.yellowAccent, fontSize: 28, fontWeight: FontWeight.bold),
      ),
    );
  }
}
