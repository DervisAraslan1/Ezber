import 'package:flutter/material.dart';

const _font = 'Manrope';

const accentDay = Color(0xFF1E6B5C);
const accentNight = Color(0xFF7FD1BC);
const flame = Color(0xFFD9822B);

/// Answer colours, darkened where they sit on the light background.
const rightColor = Color(0xFF2E9A7F);
const closeColor = Color(0xFFC08A17);
const wrongColor = Color(0xFFD9593F);

ThemeData _theme(ColorScheme scheme) => ThemeData(
      useMaterial3: true,
      fontFamily: _font,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleTextStyle: TextStyle(
          fontFamily: _font,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: scheme.onSurface,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(56),
          textStyle: const TextStyle(
            fontFamily: _font,
            fontSize: 17,
            fontWeight: FontWeight.w700,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        surfaceTintColor: Colors.transparent,
      ),
    );

final lightTheme = _theme(const ColorScheme.light(
  primary: accentDay,
  onPrimary: Colors.white,
  primaryContainer: Color(0xFFD5EAE3),
  onPrimaryContainer: Color(0xFF0C3A30),
  surface: Color(0xFFF7F3EA),
  onSurface: Color(0xFF1C1F24),
  onSurfaceVariant: Color(0xFF5A5F66),
  surfaceContainer: Color(0xFFFFFDF8),
  outlineVariant: Color(0xFFE2DCCD),
));

final darkTheme = _theme(const ColorScheme.dark(
  primary: accentNight,
  onPrimary: Color(0xFF06342B),
  primaryContainer: Color(0xFF1C4A40),
  onPrimaryContainer: Color(0xFFD5EAE3),
  surface: Color(0xFF13161B),
  onSurface: Color(0xFFECEBE6),
  onSurfaceVariant: Color(0xFFA6ABB3),
  surfaceContainer: Color(0xFF1D2128),
  outlineVariant: Color(0xFF30353E),
));
