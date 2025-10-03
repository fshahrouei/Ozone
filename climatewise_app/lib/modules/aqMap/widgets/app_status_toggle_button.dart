// lib/modules/aqMap/widgets/app_status_toggle_button.dart
//
// Small rounded toggle button for opening/closing the AppStatusInfo bar.
// Fixed width ensures consistent sizing regardless of label text length.

import 'package:flutter/material.dart';
import 'dart:ui' show FontFeature;

class AppStatusToggleButton extends StatelessWidget {
  /// Callback when the button is tapped.
  final VoidCallback onTap;

  /// Margin around the button (default: 12px on all sides).
  final EdgeInsetsGeometry margin;

  const AppStatusToggleButton({
    super.key,
    required this.onTap,
    this.margin = const EdgeInsets.all(12),
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: margin,
          width: 50,  // Fixed width for consistent appearance.
          height: 28, // Compact height, similar to ZoomIndicator.
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.6),
            borderRadius: BorderRadius.circular(20),
          ),
          alignment: Alignment.center, // Centered text alignment.
          child: const Text(
            'INFO', // Label text (fixed width ensures ellipsis if too long).
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
            overflow: TextOverflow.ellipsis, // Truncate with ellipsis if overflowing.
          ),
        ),
      ),
    );
  }
}
