// lib/modules/aqMap/models/overlay_grid.dart
//
// Overlay Grids (past) model – structured for responses from the server.
// This model is stricter than forecast grids since fields are expected
// to always be present. Used for historical/past overlay rendering.

/// A single cell in the overlay grid.
class OverlayGridCell {
  final double lat;
  final double lon;
  final double value;
  final double? cloud; // Optional cloud fraction/percent if provided.

  OverlayGridCell({
    required this.lat,
    required this.lon,
    required this.value,
    this.cloud,
  });

  factory OverlayGridCell.fromJson(Map<String, dynamic> json) {
    return OverlayGridCell(
      lat: (json['lat'] as num).toDouble(),
      lon: (json['lon'] as num).toDouble(),
      value: (json['value'] as num).toDouble(),
      cloud: json['cloud'] != null ? (json['cloud'] as num).toDouble() : null,
    );
  }
}

/// Metadata describing an overlay grid (from server).
class OverlayGridMeta {
  final String product;
  final String units;
  final String mode;        // Always "past" in this endpoint.
  final int z;              // Effective zoom level.
  final String t;           // UTC ISO timestamp string.
  final String crs;         // Coordinate reference system, e.g. EPSG:4326.
  final String cellAnchor;  // Usually "centroid".
  final String palette;

  final double bucketDeg;
  final double gridDeg;

  // Requested BBOX.
  final double bboxW;
  final double bboxS;
  final double bboxE;
  final double bboxN;

  // Effective BBOX (after server clipping).
  final double bboxEffW;
  final double bboxEffS;
  final double bboxEffE;
  final double bboxEffN;

  // Color mapping domain.
  final String domainStrategy;
  final double domainMin;
  final double domainMax;

  OverlayGridMeta({
    required this.product,
    required this.units,
    required this.mode,
    required this.z,
    required this.t,
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

  factory OverlayGridMeta.fromJson(Map<String, dynamic> json) {
    final bbox = json['bbox'] as Map<String, dynamic>;
    final bboxEff = json['bbox_effective'] as Map<String, dynamic>;
    final domain = json['domain'] as Map<String, dynamic>;

    return OverlayGridMeta(
      product: json['product'] as String,
      units: json['units'] as String,
      mode: json['mode'] as String,
      z: json['z'] as int,
      t: json['t'] as String,
      crs: json['crs'] as String,
      cellAnchor: json['cell_anchor'] as String,
      palette: json['palette'] as String,
      bucketDeg: (json['bucket_deg'] as num).toDouble(),
      gridDeg: (json['grid_deg'] as num).toDouble(),
      bboxW: (bbox['w'] as num).toDouble(),
      bboxS: (bbox['s'] as num).toDouble(),
      bboxE: (bbox['e'] as num).toDouble(),
      bboxN: (bbox['n'] as num).toDouble(),
      bboxEffW: (bboxEff['w'] as num).toDouble(),
      bboxEffS: (bboxEff['s'] as num).toDouble(),
      bboxEffE: (bboxEff['e'] as num).toDouble(),
      bboxEffN: (bboxEff['n'] as num).toDouble(),
      domainStrategy: domain['strategy'] as String,
      domainMin: (domain['min'] as num).toDouble(),
      domainMax: (domain['max'] as num).toDouble(),
    );
  }
}

/// Full server response for overlay grids.
class OverlayGridResponse {
  final bool succeed;
  final int status;
  final OverlayGridMeta meta;
  final List<OverlayGridCell> cells;
  final int cellsCount;
  final String? hint; // Optional server hint if cells_count=0.

  OverlayGridResponse({
    required this.succeed,
    required this.status,
    required this.meta,
    required this.cells,
    required this.cellsCount,
    this.hint,
  });

  factory OverlayGridResponse.fromJson(Map<String, dynamic> json) {
    return OverlayGridResponse(
      succeed: json['succeed'] as bool,
      status: json['status'] as int,
      meta: OverlayGridMeta.fromJson(json),
      cells: (json['cells'] as List<dynamic>)
          .map((c) => OverlayGridCell.fromJson(c as Map<String, dynamic>))
          .toList(),
      cellsCount: json['cells_count'] as int,
      hint: json['hint'] as String?,
    );
  }
}
