// lib/modules/aqMap/widgets/station_details_sheet.dart
//
// Minimal station sheet (uses your StationPoint model).
// Shows exactly 4 fields:
// 1) Source name      (from point.provider)
// 2) Measured value   (point.val + unit by current product)
// 3) Data age         (from point.ageH → pretty minutes/hours)
// 4) Coordinates      (point.lat, point.lon)
//
// Taps on a pin should call: StationDetailsSheet(controller: c, point: p)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../controllers/aq_map_controller.dart';
import '../models/stations_model.dart';

class StationDetailsSheet extends StatelessWidget {
  final AqMapController controller;
  final StationPoint point;

  const StationDetailsSheet({
    super.key,
    required this.controller,
    required this.point,
  });

  // Unit decides by currently active map product
  String _unitFor(String product) {
    switch (product) {
      case 'no2':
      case 'hcho':
        return 'molecules/cm²';
      case 'o3tot':
        return 'DU';
      case 'cldo4':
        return 'fraction';
      default:
        return '';
    }
  }

  String _fmtAge(double? ageH) {
    if (ageH == null || ageH.isNaN || !ageH.isFinite) return '—';
    final mins = (ageH * 60).round();
    if (mins < 1) return '<1 min';
    if (mins < 60) return '$mins mins';
    final h = (mins / 60).floor();
    final rem = mins % 60;
    return rem == 0 ? '$h h' : '$h h ${rem}m';
  }

  String _fmtVal(num? v) {
    if (v == null) return '—';
    // nice, short formatting
    if (v.abs() >= 1e6) return v.toStringAsExponential(2);
    if (v.abs() >= 1000) return NumberFormat('#,##0').format(v);
    if (v == v.roundToDouble()) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }

  String _fmtCoords(double lat, double lon) =>
      '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final sourceName =
        (point.provider ?? '').toString().trim().isEmpty ? 'Station' : point.provider!;
    final valueStr = _fmtVal(point.val);
    final ageStr = _fmtAge(point.ageH);
    final coordsStr = _fmtCoords(point.lat, point.lon);
    final unit = _unitFor(controller.product);

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          boxShadow: const [BoxShadow(blurRadius: 18, color: Colors.black26)],
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // drag handle
            Container(
              width: 42,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: cs.outline.withOpacity(.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // header row
            Row(
              children: [
                Icon(Icons.sensors_outlined, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    sourceName,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ],
            ),
            const SizedBox(height: 6),

            // list of the 4 items
            _row(
              context,
              icon: Icons.timeline_rounded,
              label: 'Measured value',
              value: unit.isNotEmpty ? '$valueStr $unit' : valueStr,
            ),
            _row(
              context,
              icon: Icons.schedule_rounded,
              label: 'Data age',
              value: ageStr,
            ),
            _row(
              context,
              icon: Icons.place_outlined,
              label: 'Coordinates',
              value: coordsStr,
            ),
            _row(
              context,
              icon: Icons.cloud_outlined,
              label: 'Source',
              value: sourceName,
            ),

            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withOpacity(0.75),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 2,
            child: Text(
              value,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
