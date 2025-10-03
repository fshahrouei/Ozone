import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Reminder: IRANSansX font must be declared in pubspec.yaml
/// flutter:
///   fonts:
///     - family: IRANSansX
///       fonts:
///         - asset: assets/fonts/IRANSansX-Regular.ttf
///         - asset: assets/fonts/IRANSansX-Medium.ttf
///           weight: 500
///         - asset: assets/fonts/IRANSansX-Bold.ttf
///           weight: 700

// --- Light Theme ---
final ThemeData lightTheme = _buildLightTheme();

// --- Dark Theme ---
final ThemeData darkTheme = _buildDarkTheme();

ThemeData _buildLightTheme() {
  final base = ThemeData.light(useMaterial3: true);

  return base.copyWith(
    primaryColor: Colors.blue[500],
    cardColor: Colors.grey.shade300,

    appBarTheme: AppBarTheme(
      backgroundColor: Colors.blue[500],
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.blue.shade600,
        statusBarIconBrightness: Brightness.light,
      ),
      titleTextStyle: const TextStyle(
        fontFamily: 'IRANSansX',
        color: Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: 18,
      ),
    ),

    textTheme: base.textTheme.apply(
      fontFamily: 'IRANSansX',
      bodyColor: Colors.black,
      displayColor: Colors.black,
    ).copyWith(
      titleLarge: const TextStyle(
        fontFamily: 'IRANSansX',
        color: Colors.black,
        letterSpacing: 3.0,
        fontWeight: FontWeight.bold,
        fontSize: 22,
      ),
    ),

    buttonTheme: ButtonThemeData(
      buttonColor: Colors.blue[600],
    ),
  );
}

ThemeData _buildDarkTheme() {
  final base = ThemeData.dark(useMaterial3: true);

  return base.copyWith(
    primaryColor: Colors.blue[700],
    scaffoldBackgroundColor: const Color(0xFF1F2937),
    cardColor: const Color(0xFF374151),

    appBarTheme: AppBarTheme(
      backgroundColor: Colors.blue[700],
      foregroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.blue.shade800,
        statusBarIconBrightness: Brightness.light,
        systemNavigationBarIconBrightness: Brightness.light,
      ),
      titleTextStyle: const TextStyle(
        fontFamily: 'IRANSansX',
        color: Colors.white,
        fontWeight: FontWeight.w700,
        fontSize: 18,
      ),
    ),

    textTheme: base.textTheme.apply(
      fontFamily: 'IRANSansX',
      bodyColor: Colors.white,
      displayColor: Colors.white,
    ).copyWith(
      titleLarge: const TextStyle(
        fontFamily: 'IRANSansX',
        color: Colors.white,
        letterSpacing: 3.5,
        fontWeight: FontWeight.bold,
        fontSize: 16,
      ),
    ),

    buttonTheme: ButtonThemeData(
      buttonColor: Colors.blue[700],
    ),
  );
}
