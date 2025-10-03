import 'package:flutter/material.dart';
import 'dart:ui' show FontFeature;

import '../controllers/aq_map_controller.dart';
import 'point_assess_sheet.dart';

/// Floating pill-style button, styled similar to AppStatusToggleButton:
/// - Wrapped in SafeArea + GestureDetector
/// - Height fixed at 28
/// - Blue semi-transparent background
/// - White text with ellipsis if label is too long
class PointAssessFab extends StatelessWidget {
  final AqMapController controller;

  /// Margin from surrounding widgets (default: 5px right, 12px bottom).
  final EdgeInsetsGeometry margin;

  const PointAssessFab({
    super.key,
    required this.controller,
    this.margin = const EdgeInsets.only(right: 5, bottom: 12),
  });

  /// Build label text depending on forecast selection.
  String _label() {
    final bool isForecast = controller.isForecast;
    final int h = controller.selectedForecastHour ?? 0;
    if (isForecast && h > 0) {
      return 'Forecast +${h}h';
    }
    return 'Forecast Now';
  }

  @override
  Widget build(BuildContext context) {
    final text = _label();

    return SafeArea(
      child: GestureDetector(
        onTap: () async {
          await showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            useSafeArea: true,
            backgroundColor: Colors.transparent,
            builder: (_) => PointAssessSheet(controller: controller),
          );
        },
        child: Container(
          margin: margin,
          height: 28, // Same fixed height as AppStatusToggleButton
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.6),
            borderRadius: BorderRadius.circular(20),
          ),
          alignment: Alignment.center,
          child: Text(
            text, // Ellipsis if label is too long
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
        ),
      ),
    );
  }
}
