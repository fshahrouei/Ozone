import 'package:flutter/material.dart';

/// Header section used on the About page.
/// Displays the app logo, project title, and a short description.
class LogoHeader extends StatelessWidget {
  const LogoHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Logo container with light background and subtle shadow
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          padding: const EdgeInsets.all(14),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.asset(
              'assets/images/shared/aqi_logo.png',
              width: 88,
              height: 88,
              fit: BoxFit.contain,
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Title
        Text(
          'ClimateWise Project',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 20.5,
            color: Colors.grey[800],
            letterSpacing: 0.3,
          ),
        ),

        const SizedBox(height: 8),

        // Short description
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28.0),
          child: Text(
            "An introduction to climate and air pollution, highlighting air-quality forecasts, global warming trends, greenhouse-gas emissions, and health impacts — showing how the planet is changing.",
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.5,
              color: Colors.grey[700],
              height: 1.7,
            ),
          ),
        ),
      ],
    );
  }
}
