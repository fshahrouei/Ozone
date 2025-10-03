import 'package:flutter/material.dart';
import '../../../core/widgets/main_navigation.dart';

/// LoginScreen
///
/// A simple login page with two flows:
/// - Regular login (navigates to MainNavigation)
/// - Guest login (navigates to MainNavigation without credentials)
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  void _onLogin(BuildContext context) {
    // TODO: Place real login logic here
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainNavigation()),
    );
  }

  void _onGuest(BuildContext context) {
    // Guest login flow
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const MainNavigation()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const TextField(
              decoration: InputDecoration(labelText: 'Username'),
            ),
            const SizedBox(height: 16),
            const TextField(
              obscureText: true,
              decoration: InputDecoration(labelText: 'Password'),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => _onLogin(context),
              child: const Text('Login'),
            ),
            TextButton(
              onPressed: () => _onGuest(context),
              child: const Text('Continue as Guest'),
            ),
          ],
        ),
      ),
    );
  }
}
