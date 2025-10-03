import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../../aqMap/data/aq_map_repository.dart';
import '../../aqMap/controllers/aq_map_controller.dart';
import '../../aqMap/widgets/point_assess_sheet.dart';

class ForecastNowBridge {
  static Future<void> open(
    BuildContext context, {
    required double lat,
    required double lon,
    int tHours = 0,
    Map<String, double>? weights,
    bool debug = false,
  }) async {
    try {
      final repo = AqMapRepository();
      final ctrl = AqMapController(repository: repo);

      // Optional: clamp to server precision like the form does (4 decimals).
      final ll = LatLng(
        double.parse(lat.toStringAsFixed(4)),
        double.parse(lon.toStringAsFixed(4)),
      );

      await showModalBottomSheet(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: Colors.transparent,
        builder: (_) => PointAssessSheet(
          controller: ctrl,
          point: ll,
          tHours: tHours.clamp(0, 12),
          weights: weights,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to open forecast: $e'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
}
