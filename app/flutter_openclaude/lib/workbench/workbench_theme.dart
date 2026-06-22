import 'package:flutter/material.dart';

ThemeData buildWorkbenchTheme() {
  const accent = Color(0xFF2563EB);
  const background = Color(0xFFF4F5F7);
  const surface = Color(0xFFFFFFFF);
  const outline = Color(0xFFD9DEE7);

  return ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.light,
      surface: surface,
    ),
    scaffoldBackgroundColor: background,
    dividerColor: outline,
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      isDense: true,
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: outline),
      ),
    ),
  );
}
