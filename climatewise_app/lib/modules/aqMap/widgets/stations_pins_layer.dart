// lib/modules/aqMap/widgets/stations_pins_layer.dart
//
// A very lightweight pins layer for station points on flutter_map.
// - Requires controller to keep API symmetric with the rest of the map widgets.
// - Renders markers only when current zoom >= minZoomToShow.
// - Tapping a pin calls onTapPoint(point).
//
// If you later switch to clustering, replace MarkerLayer with the
// appropriate cluster layer and keep the same constructor contract.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../controllers/aq_map_controller.dart';
import '../models/stations_model.dart';

class StationsPinsLayer extends StatelessWidget {
  final AqMapController controller;              // ✅ required (to match your app pattern)
  final List<StationPoint> points;               // ✅ required
  final double? currentZoom;                     // for visibility control / sizing
  final double minZoomToShow;                    // default 8.0
  final ValueChanged<StationPoint>? onTapPoint;  // callback on tap

  const StationsPinsLayer({
    super.key,
    required this.controller,
    required this.points,
    this.currentZoom,
    this.minZoomToShow = 8.0,
    this.onTapPoint,
  });

  @override
  Widget build(BuildContext context) {
    final zoom = currentZoom ?? controller.zoom; // fallback to controller if provided
    final show = (zoom >= minZoomToShow);

    if (!show || points.isEmpty) {
      // Return an empty layer so the list of children stays compatible.
      return const MarkerLayer(markers: <Marker>[]);
    }

    // Basic size scaling with zoom (optional and gentle)
    final double baseSize = 28.0;
    final double size = (zoom <= minZoomToShow)
        ? baseSize
        : (baseSize + (zoom - minZoomToShow) * 2.0).clamp(baseSize, 40.0);

    final markers = points.map((p) {
      return Marker(
        point: LatLng(p.lat, p.lon),
        width: size,
        height: size,
        alignment: Alignment.center,
        child: _Pin(
          value: p.val,
          onTap: () => onTapPoint?.call(p),
        ),
      );
    }).toList(growable: false);

    return MarkerLayer(markers: markers);
  }
}

class _Pin extends StatelessWidget {
  final double? value;
  final VoidCallback? onTap;

  const _Pin({this.value, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Simple color scale: low -> green, mid -> amber, high -> red
    Color colorFor(double? v) {
      if (v == null) return cs.primary;
      if (v <= 10) return Colors.green;
      if (v <= 30) return Colors.orange;
      return Colors.red;
    }

    final pinColor = colorFor(value);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: pinColor.withValues(alpha: 0.9),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.white.withValues(alpha: 0.9), width: 2),
        ),
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(4.0),
          child: FittedBox(
            child: Text(
              (value == null) ? '—' : value!.toStringAsFixed(value! < 10 ? 1 : 0),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
