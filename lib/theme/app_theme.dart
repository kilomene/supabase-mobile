import 'package:flutter/material.dart';

/// Approved visual direction 2026-11-09: dark theme, Supabase green.
/// Matches the 11 previews in ~/workspace/supabase-mobile/previews/.
class AppTheme {
  static const green = Color(0xFF3ECF8E);
  static const background = Color(0xFF0B0D0F);
  static const surface = Color(0xFF171A1E);
  static const surface2 = Color(0xFF22262C);
  static const text = Color(0xFFF5F5F5);
  static const muted = Color(0xFF9AA0A6);

  static final dark = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    colorScheme: const ColorScheme.dark(
      primary: green,
      surface: surface,
      onSurface: text,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      foregroundColor: text,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: green,
        foregroundColor: Colors.black,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface2,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    ),
    useMaterial3: true,
  );
}
