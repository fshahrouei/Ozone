import 'package:flutter/material.dart';
import 'package:climatewise/modules/onboarding/screens/onboarding_screen.dart';
import 'package:climatewise/modules/auth/screens/login_screen.dart';
import 'package:climatewise/core/widgets/main_navigation.dart';
// import 'package:climatewise/modules/update/screens/update_screen.dart';

/// AppRoutes
///
/// Centralized route definitions for the application.
/// - Keeps all route names and widget mappings in one place.
/// - Makes navigation consistent and avoids hardcoded strings.
///
/// Usage:
/// ```dart
/// Navigator.pushNamed(context, AppRoutes.login);
/// ```
class AppRoutes {
  static const String onboarding = '/';
  static const String login = '/login';
  static const String main = '/main';
  // static const String update = '/update';

  /// Maps route names to their corresponding widget builders.
  static Map<String, WidgetBuilder> routes = {
    onboarding: (context) => const OnBoardingScreen(),
    login: (context) => const LoginScreen(),
    main: (context) => const MainNavigation(),
    // update: (context) => const UpdateScreen(),
  };
}
