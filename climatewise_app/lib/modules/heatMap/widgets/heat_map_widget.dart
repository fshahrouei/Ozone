import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map_geojson2/flutter_map_geojson2.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/heat_data.dart';

/// Heat map widget that:
/// - Renders OSM tiles
/// - Draws country polygons from a GeoJSON asset
/// - Colors polygons by anomaly score (1..10)
/// - Emits hit results via [hitNotifier] for external UI
/// - Shows an OSM copyright/attribution badge (required)
class HeatMapWidget extends StatelessWidget {
  final List<HeatData> heatData;
  final ValueNotifier<LayerHitResult<Object>?> hitNotifier;
  final MapController mapController;
  final LatLngBounds bounds;
  final LatLng mapCenter;
  final List<Color> colors;

  const HeatMapWidget({
    super.key,
    required this.heatData,
    required this.hitNotifier,
    required this.mapController,
    required this.bounds,
    required this.mapCenter,
    required this.colors,
  });

  /// Returns a color for the given [score] (1 = strong blue .. 10 = strong red).
  /// Note: Score must be computed from anomaly beforehand and be in [1, 10].
  Color _getCountryColor(int score) {
    final s = score.clamp(1, 10);
    return colors[s - 1];
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: rootBundle.loadString('assets/maps/globe.json'),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(child: Text('Error: ${snapshot.error}'));
        } else {
          return Stack(
            children: [
              FlutterMap(
                mapController: mapController,
                options: MapOptions(
                  initialCenter: mapCenter,
                  initialZoom: 2,
                  minZoom: 2,
                  maxZoom: 5,
                  interactionOptions: InteractionOptions(
                    flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    rotationThreshold: 360.0,
                  ),
                  cameraConstraint: CameraConstraint.contain(bounds: bounds),
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'cloud.dinamit.climatewise',
                  ),
                  GeoJsonLayer.asset(
                    'assets/maps/globe.json',
                    hitNotifier: hitNotifier,
                    onPolygon: (
                      List<LatLng> points,
                      List<List<LatLng>>? holes,
                      Map<String, dynamic> properties,
                    ) {
                      final isoA3 = properties['iso_a3'];
                      final heat = heatData.firstWhere(
                        (data) => data.isoA3 == isoA3,
                        orElse: () => HeatData(
                          isoA3: isoA3,
                          tas: 0,
                          anomaly: 0,
                          score: 1,
                        ),
                      );
                      return Polygon(
                        points: points,
                        color: _getCountryColor(heat.score).withOpacity(0.7),
                        borderColor: Colors.black54,
                        borderStrokeWidth: 1.0,
                        hitValue: isoA3,
                      );
                    },
                  ),
                ],
              ),

              /// OSM attribution badge (required by OSM terms).
              /// Tapping opens the copyright page.
              const _OsmAttributionBadge(),
            ],
          );
        }
      },
    );
  }
}

/// Small clickable badge for OSM attribution.
/// Appears above the map in the bottom-left corner.
class _OsmAttributionBadge extends StatelessWidget {
  const _OsmAttributionBadge();

  static final Uri _osmCopyright =
      Uri.parse('https://www.openstreetmap.org/copyright');

  Future<void> _openAttribution() async {
    await launchUrl(_osmCopyright, mode: LaunchMode.externalApplication);
  }

@override
Widget build(BuildContext context) {
  return Positioned(
    left: 12,
    bottom: 12,
    child: SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.3), // 30% black background
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          '@ OSM',
          style: TextStyle(
            fontSize: 11.5,
            color: Colors.white,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    ),
  );
}

}
