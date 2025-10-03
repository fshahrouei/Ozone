// lib/modules/healthAdvisor/widgets/health_form/map_picker.dart

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';

/// Geographic clamp for North America to prevent panning far away.
final LatLngBounds kNorthAmericaBounds = LatLngBounds(
  const LatLng(7.0, -168.0),
  const LatLng(83.0, -52.0),
);

LatLng clampToNorthAmerica(LatLng p) {
  final b = kNorthAmericaBounds;
  final clampedLat = p.latitude.clamp(b.south, b.north);
  final clampedLon = p.longitude.clamp(b.west, b.east);
  return LatLng(clampedLat.toDouble(), clampedLon.toDouble());
}

/// Default fallback when user location is unavailable or outside bounds.
const LatLng kManhattanNY = LatLng(40.7831, -73.9712);

class MapLatLonPicker extends StatelessWidget {
  final MapController controller;
  final LatLng current;
  final bool hasSelection;
  final LatLng defaultCenter;
  final VoidCallback onOpenFullscreen;

  const MapLatLonPicker({
    super.key,
    required this.controller,
    required this.current,
    required this.hasSelection,
    required this.defaultCenter,
    required this.onOpenFullscreen,
  });

  @override
  Widget build(BuildContext context) {
    final bounds = kNorthAmericaBounds;
    final pin = hasSelection ? current : defaultCenter;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        height: 220,
        child: Stack(
          children: [
            FlutterMap(
              mapController: controller,
              options: MapOptions(
                initialCenter: pin,
                initialZoom: hasSelection ? 10 : 3,
                interactionOptions: const InteractionOptions(flags: InteractiveFlag.none),
                onTap: (tapPos, _) => onOpenFullscreen(),
                onMapEvent: (_) {
                  final cam = controller.camera;
                  if (!bounds.contains(cam.center)) {
                    controller.move(clampToNorthAmerica(cam.center), cam.zoom);
                  }
                },
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'cloud.dinamit.climatewise',
                  tileBounds: bounds,
                  minZoom: 3,
                  maxZoom: 18,
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: pin,
                      width: 30,
                      height: 30,
                      child: const Icon(Icons.location_pin, color: Colors.red, size: 30),
                    )
                  ],
                ),
              ],
            ),
            _watermark(left: 6, label: 'Tap map to pick'),
            _watermark(right: 6, label: '© OpenStreetMap contributors'),
          ],
        ),
      ),
    );
  }

  Positioned _watermark({double? left, double? right, required String label}) {
    return Positioned(
      left: left,
      right: right,
      bottom: 6,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.35),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
        ),
      ),
    );
  }
}

class FullscreenMapPicker extends StatefulWidget {
  final LatLng initial;
  const FullscreenMapPicker({super.key, required this.initial});

  @override
  State<FullscreenMapPicker> createState() => _FullscreenMapPickerState();
}

class _FullscreenMapPickerState extends State<FullscreenMapPicker> {
  final MapController _controller = MapController();
  late LatLng _picked;

  @override
  void initState() {
    super.initState();
    _picked = clampToNorthAmerica(widget.initial);
  }

  /// Centers the map to the user's current position when permitted,
  /// otherwise falls back to Manhattan, NY.
  Future<void> _goToMyLocation() async {
    LatLng target = kManhattanNY;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _snack('Location services are disabled. Falling back to Manhattan, NY.');
      } else {
        var perm = await Geolocator.checkPermission();
        if (perm == LocationPermission.denied) {
          perm = await Geolocator.requestPermission();
        }
        if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
          _snack('Location permission denied. Falling back to Manhattan, NY.');
        } else {
          final pos = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 8),
          );
          final raw = LatLng(pos.latitude, pos.longitude);
          target = kNorthAmericaBounds.contains(raw) ? raw : kManhattanNY;
          if (!kNorthAmericaBounds.contains(raw)) {
            _snack('Current position is outside North America → using Manhattan, NY.');
          }
        }
      }
    } catch (_) {
      _snack('Failed to get location → using Manhattan, NY.');
      target = kManhattanNY;
    }

    target = clampToNorthAmerica(target);
    setState(() => _picked = target);
    _controller.move(target, 10);
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bounds = kNorthAmericaBounds;

    return Scaffold(
      appBar: AppBar(title: const Text('Pick a location')),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _controller,
            options: MapOptions(
              initialCenter: _picked,
              initialZoom: 10,
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
              onTap: (tapPos, p) {
                final f = clampToNorthAmerica(p);
                setState(() => _picked = f);
                _controller.move(f, _controller.camera.zoom);
              },
              onMapEvent: (_) {
                final cam = _controller.camera;
                if (!bounds.contains(cam.center)) {
                  _controller.move(clampToNorthAmerica(cam.center), cam.zoom);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'cloud.dinamit.climatewise',
                tileBounds: bounds,
                minZoom: 3,
                maxZoom: 18,
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: _picked,
                    width: 36,
                    height: 36,
                    child: const Icon(Icons.location_pin, color: Colors.red, size: 36),
                  )
                ],
              ),
            ],
          ),

          // "My location" button: translucent chip with spacing from top/left.
          Positioned(
            top: 12,
            left: 12,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _goToMyLocation,
                borderRadius: BorderRadius.circular(6),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(.35),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.my_location, color: Colors.white, size: 22),
                  ),
                ),
              ),
            ),
          ),

          // Lat/Lon readout (glass-like background).
          Positioned(
            left: 12,
            right: 12,
            bottom: 84,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(.35),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Text(
                  'Lat: ${_picked.latitude.toStringAsFixed(5)}  •  Lon: ${_picked.longitude.toStringAsFixed(5)}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),

          _watermark(right: 8, label: '© OpenStreetMap contributors'),
        ],
      ),
      // Bottom action bar with subtle rounded corners and brand-like colors.
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.red.shade200,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                ),
                onPressed: () => Navigator.pop<LatLng?>(context, null),
                child: const Text('Cancel'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
                ),
                onPressed: () => Navigator.pop<LatLng>(context, _picked),
                child: const Text('Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Positioned _watermark({double? left, double? right, required String label}) {
    return Positioned(
      left: left,
      right: right,
      bottom: 8,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.35),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
        ),
      ),
    );
  }
}
