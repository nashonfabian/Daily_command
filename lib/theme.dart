import 'package:flutter/material.dart';

class AppTheme {
  static const charcoal = Color(0xFF1E242C);
  static const navy = Color(0xFF1C2833);
  static const offWhite = Color(0xFFF8F5F0);
  static const restGreen = Color(0xFF2E7D5B);
  static const mutedGrey = Color(0xFF8A94A6);
  static const cardWhite = Colors.white;

  static ThemeData get light {
    return ThemeData(
      scaffoldBackgroundColor: offWhite,
      primaryColor: charcoal,
      colorScheme: const ColorScheme.light(
        primary: charcoal,
        secondary: restGreen,
        surface: cardWhite,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: charcoal, letterSpacing: -0.5),
        titleLarge: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: charcoal),
        bodyLarge: TextStyle(fontSize: 16, color: charcoal, height: 1.5),
        bodyMedium: TextStyle(fontSize: 14, color: Color(0xFF4A5568)),
        labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.5),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: offWhite,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: charcoal, letterSpacing: -0.5),
      ),
      cardTheme: const CardTheme(
        color: cardWhite,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16)), side: BorderSide(color: Color(0x0F000000))),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: charcoal,
          foregroundColor: Colors.white,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, letterSpacing: 0.5),
        ),
      ),
    );
  }
}
