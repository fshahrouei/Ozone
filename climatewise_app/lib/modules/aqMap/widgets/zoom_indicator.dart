// lib/modules/aqMap/widgets/zoom_indicator.dart
//
// Zoom indicator widget. Displays the current zoom level as a pill.
// - Can be tapped to toggle/open a zoom panel if [onTap] is provided
// - If [active] is true, styles are more prominent to indicate panel is open

import 'package:flutter/material.dart';
import 'dart:ui' show FontFeature;

class ZoomIndicator extends StatelessWidget {
  /// Current zoom value.
  final double zoom;

  /// Margin around the pill container.
  final EdgeInsetsGeometry margin;

  /// Optional tap callback; if null, pill is non-interactive.
  final VoidCallback? onTap;

  /// Whether the zoom panel is currently open; affects styling.
  final bool active;

  const ZoomIndicator({
    super.key,
    required this.zoom,
    this.margin = const EdgeInsets.all(12),
    this.onTap,
    this.active = false,
  });

  @override
  Widget build(BuildContext context) {
    final txt = zoom.toStringAsFixed(2); // Example: "10.25"
    final bg = active
        ? Colors.black.withOpacity(0.75)
        : Colors.black.withOpacity(0.60);

    final pill = Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: active
            ? Border.all(color: Colors.white.withOpacity(0.5), width: 1)
            : null,
      ),
      child: Text(
        'Zoom: $txt',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );

    if (onTap == null) {
      return SafeArea(child: pill);
    }

    return SafeArea(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: pill,
      ),
    );
  }
}
