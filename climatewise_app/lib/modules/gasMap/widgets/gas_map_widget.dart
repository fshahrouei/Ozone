// lib/modules/gasMap/widgets/gas_map_widget.dart
//
// GasMapWidget
// -------------
// Stateless map widget that renders a world choropleth using a local GeoJSON
// and colors each country by its score (1..10). Taps are reported via
// `hitNotifier` (from flutter_map_geojson2) so the parent can react to hits.
//
// NOTE:
// - No logic changes vs your original. Only English, standard-style comments.
// - The internal loader in the FutureBuilder is typically not visible because
//   this widget is built after the asset is already cached/available.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_map_geojson2/flutter_map_geojson2.dart';

import '../models/gas_data.dart';

class GasMapWidget extends StatelessWidget {
  /// Data rows per country (iso_a3, total, score).
  final List<GasData> gasData;

  /// Emits hit results when the user taps polygons (countries).
  final ValueNotifier<LayerHitResult<Object>?> hitNotifier;

  /// External map controller to allow the parent to manipulate the camera.
  final MapController mapController;

  /// Hard camera constraint (e.g., clamp to North America or world).
  final LatLngBounds bounds;

  /// Initial map center.
  final LatLng mapCenter;

  /// Ten colors (index 0..9) for score 1..10 respectively.
  final List<Color> colors;

  const GasMapWidget({
    super.key,
    required this.gasData,
    required this.hitNotifier,
    required this.mapController,
    required this.bounds,
    required this.mapCenter,
    required this.colors,
  });

  /// Maps a 1..10 score to the provided color palette (index 0..9).
  Color _getCountryColor(int score) {
    score = score.clamp(1, 10);
    return colors[score - 1];
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      // Preload the same asset used by GeoJsonLayer to surface errors early.
      future: rootBundle.loadString('assets/maps/globe.json'),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Typically not shown because this widget is constructed after load.
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          return Center(child: Text('Error loading map asset: ${snapshot.error}'));
        } else {
          return FlutterMap(
            mapController: mapController,
            options: MapOptions(
              initialCenter: mapCenter,
              initialZoom: 2,
              minZoom: 2,
              maxZoom: 5,
              interactionOptions: InteractionOptions(
                // Disable rotation for simpler UX.
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                rotationThreshold: 360.0,
              ),
              // Keep the camera inside the provided bounds.
              cameraConstraint: CameraConstraint.contain(bounds: bounds),
            ),
            children: [
              // Base raster tiles (OSM). Consider adding an attribution widget
              // elsewhere in the screen to comply with OSM terms.
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'cloud.dinamit.climatewise',
              ),

              // Country polygons from local GeoJSON. Each polygon is colored
              // by score and publishes its iso_a3 via hitValue.
              GeoJsonLayer.asset(
                'assets/maps/globe.json',
                hitNotifier: hitNotifier,
                onPolygon: (
                  List<LatLng> points,
                  List<List<LatLng>>? holes,
                  Map<String, dynamic> properties,
                ) {
                  final isoA3 = properties['iso_a3'];
                  final gas = gasData.firstWhere(
                    (d) => d.isoA3 == isoA3,
                    orElse: () => GasData(isoA3: isoA3, total: '0', score: 1),
                  );
                  return Polygon(
                    points: points,
                    color: _getCountryColor(gas.score).withOpacity(0.6),
                    borderColor: Colors.black54,
                    borderStrokeWidth: 1.0,
                    hitValue: isoA3,
                  );
                },
              ),
            ],
          );
        }
      },
    );
  }
}
