// lib/modules/aqMap/models/forecast_grid.dart
//
// Forecast Grids (future) model – intentionally isolated from the Overlay
// Grids model. Designed to be resilient against missing/nullable fields to
// avoid CastErrors and keep parsing robust.

import 'package:flutter/material.dart';

/// A single grid cell in a forecast-grids response.
class ForecastGridCell {
  final double lat;
  final double lon;
  final double value;
  final double? cloud; // Optional cloud fraction/percent if provided by server.

  ForecastGridCell({
    required this.lat,
    required this.lon,
    required this.value,
    this.cloud,
  });

  factory ForecastGridCell.fromJson(Map<String, dynamic> json) {
    return ForecastGridCell(
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      value: (json['value'] as num).toDouble(),
      cloud: json['cloud'] != null ? (json['cloud'] as num).toDouble() : null,
    );
  }
}

/// Metadata block coming with the forecast-grids response.
class ForecastGridMeta {
  final String product;
  final String units;
  final String mode;     // Expected: "future".
  final int z;           // zEff (9..11) or server echo.
  final String t;        // UTC ISO timestamp from server.
  final String? tLabel;  // e.g. "+6" (optional).
  final String crs;
  final String cellAnchor; // Typically "centroid".
  final String palette;

  final double bucketDeg;
  final double gridDeg;  // Default to 0.1° if server omits it.

  // Requested BBOX
  final double bboxW;
  final double bboxS;
  final double bboxE;
  final double bboxN;

  // Effective BBOX (may be null)
  final double? bboxEffW;
  final double? bboxEffS;
  final double? bboxEffE;
  final double? bboxEffN;

  // Color mapping domain
  final String domainStrategy; // e.g. "auto" | "fixed"
  final double domainMin;
  final double domainMax;

  ForecastGridMeta({
    required this.product,
    required this.units,
    required this.mode,
    required this.z,
    required this.t,
    required this.tLabel,
    required this.crs,
    required this.cellAnchor,
    required this.palette,
    required this.bucketDeg,
    required this.gridDeg,
    required this.bboxW,
    required this.bboxS,
    required this.bboxE,
    required this.bboxN,
    required this.bboxEffW,
    required this.bboxEffS,
    required this.bboxEffE,
    required this.bboxEffN,
    required this.domainStrategy,
    required this.domainMin,
    required this.domainMax,
  });

  factory ForecastGridMeta.fromJson(Map<String, dynamic> json) {
    // Safe pick helper for nested BBOX maps.
    Map<String, dynamic> pickBox(String key) {
      final raw = json[key];
      if (raw is Map<String, dynamic>) return raw;
      return const {};
    }

    // Prefer `bbox`, then fall back to common alternates.
    Map<String, dynamic> bbox = pickBox('bbox');
    if (bbox.isEmpty) {
      bbox = pickBox('bbox_requested');
      if (bbox.isEmpty) bbox = pickBox('bbox_clipped');
    }
    final bboxEff = pickBox('bbox_effective');

    // Domain may be absent or partial.
    final domainRaw = json['domain'];
    final Map<String, dynamic> domain =
        (domainRaw is Map<String, dynamic>) ? domainRaw : const {};

    final String product = (json['product'] as String?) ?? '';
    final String units = (json['units'] as String?) ?? '';
    final String mode = (json['mode'] as String?) ?? 'future';
    final int z = (json['z'] as num?)?.toInt() ?? 9;
    final String t = (json['t'] as String?) ?? '';
    final String? tLabel = json['t_label'] as String?;
    final String crs = (json['crs'] as String?) ?? 'EPSG:4326';
    final String cellAnchor = (json['cell_anchor'] as String?) ?? 'centroid';
    final String palette = (json['palette'] as String?) ?? 'default';

    final double bucketDeg = (json['bucket_deg'] as num?)?.toDouble() ?? 0.25;
    final double gridDeg = (json['grid_deg'] as num?)?.toDouble() ?? 0.1;

    // If BBOX is entirely missing, use broad fallbacks to avoid zeros.
    final double bboxW = (bbox['w'] as num?)?.toDouble() ?? -180.0;
    final double bboxS = (bbox['s'] as num?)?.toDouble() ?? -90.0;
    final double bboxE = (bbox['e'] as num?)?.toDouble() ?? 180.0;
    final double bboxN = (bbox['n'] as num?)?.toDouble() ?? 90.0;

    final double? bboxEffW =
        bboxEff.isNotEmpty ? (bboxEff['w'] as num?)?.toDouble() : null;
    final double? bboxEffS =
        bboxEff.isNotEmpty ? (bboxEff['s'] as num?)?.toDouble() : null;
    final double? bboxEffE =
        bboxEff.isNotEmpty ? (bboxEff['e'] as num?)?.toDouble() : null;
    final double? bboxEffN =
        bboxEff.isNotEmpty ? (bboxEff['n'] as num?)?.toDouble() : null;

    final String domainStrategy = (domain['strategy'] as String?) ?? 'auto';
    final double domainMin = (domain['min'] as num?)?.toDouble() ?? 0.0;
    final double domainMax = (domain['max'] as num?)?.toDouble() ?? 1.0;

    return ForecastGridMeta(
      product: product,
      units: units,
      mode: mode,
      z: z,
      t: t,
      tLabel: tLabel,
      crs: crs,
      cellAnchor: cellAnchor,
      palette: palette,
      bucketDeg: bucketDeg,
      gridDeg: gridDeg,
      bboxW: bboxW,
      bboxS: bboxS,
      bboxE: bboxE,
      bboxN: bboxN,
      bboxEffW: bboxEffW,
      bboxEffS: bboxEffS,
      bboxEffE: bboxEffE,
      bboxEffN: bboxEffN,
      domainStrategy: domainStrategy,
      domainMin: domainMin,
      domainMax: domainMax,
    );
  }
}

/// Full server response for forecast-grids.
class ForecastGridResponse {
  final bool succeed;
  final int status;
  final ForecastGridMeta meta;
  final List<ForecastGridCell> cells;
  final int cellsCount;
  final String? hint; // Optional server hint/message if present.

  ForecastGridResponse({
    required this.succeed,
    required this.status,
    required this.meta,
    required this.cells,
    required this.cellsCount,
    this.hint,
  });

  factory ForecastGridResponse.fromJson(Map<String, dynamic> json) {
    // If the upstream error was non-JSON (e.g., HTML 502), this factory
    // should normally not be called. Still, we keep casts defensive.
    final String? note = (json['hint'] ?? json['message']) as String?;

    final List<dynamic> cellsRaw = (json['cells'] as List<dynamic>?) ?? const [];
    final cells = cellsRaw
        .whereType<Map<String, dynamic>>()
        .map(ForecastGridCell.fromJson)
        .toList();

    return ForecastGridResponse(
      succeed: (json['succeed'] as bool?) ?? false,
      status: (json['status'] as num?)?.toInt() ?? 200,
      meta: ForecastGridMeta.fromJson(json),
      cells: cells,
      cellsCount: (json['cells_count'] as num?)?.toInt() ?? cells.length,
      hint: note,
    );
  }
}
