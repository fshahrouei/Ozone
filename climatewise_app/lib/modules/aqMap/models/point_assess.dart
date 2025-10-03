// lib/modules/aqMap/models/point_assess.dart
//
// Data models for "PointAssess" API:
// GET /frontend/air-quality/point-assess?... (future mode, t=+H)
//
// - Fully null-safe
// - Friendly to large numbers (uses double for raw values)
// - Resilient to missing fields (defensive parsing)
// - Includes toJson for caching/local storage
//
// NOTE: Keep this file "model-only": no HTTP or provider logic here.

import 'dart:convert';

/// Top-level response model for PointAssess API.
class PointAssessResponse {
  final bool succeed;
  final int status;
  final MetaInfo? meta;
  final RequestInfo? request;
  final LatLon? point;

  /// Map of product -> ProductAssess (e.g., "no2","hcho","o3tot")
  final Map<String, ProductAssess> products;

  final OverallScores? overall;
  final HealthSection? health;

  /// Optional debug block
  final DebugRoot? debug;

  PointAssessResponse({
    required this.succeed,
    required this.status,
    required this.meta,
    required this.request,
    required this.point,
    required this.products,
    required this.overall,
    required this.health,
    required this.debug,
  });

  factory PointAssessResponse.fromJson(Map<String, dynamic> json) {
    final productsJson = (json['products'] as Map?) ?? {};
    final products = <String, ProductAssess>{};
    productsJson.forEach((k, v) {
      if (v is Map<String, dynamic>) {
        products[k] = ProductAssess.fromJson(v);
      }
    });

    return PointAssessResponse(
      succeed: _asBool(json['succeed']) ?? false,
      status: _asInt(json['status']) ?? 0,
      meta: json['meta'] is Map<String, dynamic> ? MetaInfo.fromJson(json['meta']) : null,
      request: json['request'] is Map<String, dynamic> ? RequestInfo.fromJson(json['request']) : null,
      point: json['point'] is Map<String, dynamic> ? LatLon.fromJson(json['point']) : null,
      products: products,
      overall: json['overall'] is Map<String, dynamic> ? OverallScores.fromJson(json['overall']) : null,
      health: json['health'] is Map<String, dynamic> ? HealthSection.fromJson(json['health']) : null,
      debug: json['debug'] is Map<String, dynamic> ? DebugRoot.fromJson(json['debug']) : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'succeed': succeed,
        'status': status,
        'meta': meta?.toJson(),
        'request': request?.toJson(),
        'point': point?.toJson(),
        'products': products.map((k, v) => MapEntry(k, v.toJson())),
        'overall': overall?.toJson(),
        'health': health?.toJson(),
        'debug': debug?.toJson(),
      };

  /// Convenience: decode from raw JSON string.
  factory PointAssessResponse.fromRawJson(String raw) =>
      PointAssessResponse.fromJson(jsonDecode(raw) as Map<String, dynamic>);

  /// Convenience: encode to raw JSON string.
  String toRawJson() => jsonEncode(toJson());

  /// UI helper: true if there was partial data (some products failed)
  bool get isPartial => meta?.partial == true;

  /// UI helper: overall level label if available (Low/Moderate/High/Very High)
  String? get overallLevel => overall?.recommendedActions?.level;
}

/// meta block
class MetaInfo {
  final String? api;
  final String? version;
  final String? mode; // "future"
  final String? generatedAt;
  final String? units; // "product-specific"
  final bool? partial; // added by server when some products fail
  final List<String>? notes;

  MetaInfo({
    this.api,
    this.version,
    this.mode,
    this.generatedAt,
    this.units,
    this.partial,
    this.notes,
  });

  factory MetaInfo.fromJson(Map<String, dynamic> json) => MetaInfo(
        api: _asString(json['api']),
        version: _asString(json['version']),
        mode: _asString(json['mode']),
        generatedAt: _asString(json['generated_at']),
        units: _asString(json['units']),
        partial: _asBool(json['partial']),
        notes: (json['notes'] is List)
            ? (json['notes'] as List).map((e) => e.toString()).toList()
            : null,
      );

  Map<String, dynamic> toJson() => {
        'api': api,
        'version': version,
        'mode': mode,
        'generated_at': generatedAt,
        'units': units,
        'partial': partial,
        'notes': notes,
      };
}

/// request echo block
class RequestInfo {
  final double? lat;
  final double? lon;
  final String? t; // "+6"
  final int? zEff; // 9..11
  final List<String> products;
  final BBox? bbox;
  final Map<String, double> weights;

  RequestInfo({
    this.lat,
    this.lon,
    this.t,
    this.zEff,
    required this.products,
    this.bbox,
    required this.weights,
  });

  factory RequestInfo.fromJson(Map<String, dynamic> json) {
    final prods = <String>[];
    if (json['products'] is List) {
      for (final e in (json['products'] as List)) {
        prods.add(e.toString());
      }
    }
    final weights = <String, double>{};
    if (json['weights'] is Map) {
      (json['weights'] as Map).forEach((k, v) {
        final d = _asDouble(v);
        if (d != null) weights[k.toString()] = d;
      });
    }
    return RequestInfo(
      lat: _asDouble(json['lat']),
      lon: _asDouble(json['lon']),
      t: _asString(json['t']),
      zEff: _asInt(json['z_eff']),
      products: prods,
      bbox: json['bbox'] is Map<String, dynamic> ? BBox.fromJson(json['bbox']) : null,
      weights: weights,
    );
  }

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lon': lon,
        't': t,
        'z_eff': zEff,
        'products': products,
        'bbox': bbox?.toJson(),
        'weights': weights,
      };
}

/// simple lat/lon holder
class LatLon {
  final double? lat;
  final double? lon;

  LatLon({this.lat, this.lon});

  factory LatLon.fromJson(Map<String, dynamic> json) => LatLon(
        lat: _asDouble(json['lat']),
        lon: _asDouble(json['lon']),
      );

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lon': lon,
      };
}

/// bounding box (w,s,e,n)
class BBox {
  final double? w;
  final double? s;
  final double? e;
  final double? n;

  BBox({this.w, this.s, this.e, this.n});

  factory BBox.fromJson(Map<String, dynamic> json) => BBox(
        w: _asDouble(json['w']),
        s: _asDouble(json['s']),
        e: _asDouble(json['e']),
        n: _asDouble(json['n']),
      );

  Map<String, dynamic> toJson() => {
        'w': w,
        's': s,
        'e': e,
        'n': n,
      };
}

/// Per-product assessment block
class ProductAssess {
  final String? product; // "no2"
  final bool succeed;
  final int status;
  final String? units; // e.g., "molecules/cm^2" | "DU"
  final ValueInfo? value;
  final ScoreInfo? score;
  final PlaceInfo? place;
  final ProductMeta? meta;
  final ProductDebug? debug;
  final String? message; // when succeed=false or 204

  ProductAssess({
    this.product,
    required this.succeed,
    required this.status,
    this.units,
    this.value,
    this.score,
    this.place,
    this.meta,
    this.debug,
    this.message,
  });

  factory ProductAssess.fromJson(Map<String, dynamic> json) => ProductAssess(
        product: _asString(json['product']),
        succeed: _asBool(json['succeed']) ?? false,
        status: _asInt(json['status']) ?? 0,
        units: _asString(json['units']),
        value: json['value'] is Map<String, dynamic> ? ValueInfo.fromJson(json['value']) : null,
        score: json['score'] is Map<String, dynamic> ? ScoreInfo.fromJson(json['score']) : null,
        place: json['place'] is Map<String, dynamic> ? PlaceInfo.fromJson(json['place']) : null,
        meta: json['meta'] is Map<String, dynamic> ? ProductMeta.fromJson(json['meta']) : null,
        debug: json['debug'] is Map<String, dynamic> ? ProductDebug.fromJson(json['debug']) : null,
        message: _asString(json['message']),
      );

  Map<String, dynamic> toJson() => {
        'product': product,
        'succeed': succeed,
        'status': status,
        'units': units,
        'value': value?.toJson(),
        'score': score?.toJson(),
        'place': place?.toJson(),
        'meta': meta?.toJson(),
        'debug': debug?.toJson(),
        'message': message,
      };

  /// UI helper: returns a short label like "5.2 / 10" or null
  String? get scoreOutOf10 =>
      (score?.score10 != null) ? '${score!.score10!.toStringAsFixed(1)} / 10' : null;
}

/// value {raw, units}
class ValueInfo {
  final double? raw;
  final String? units;

  ValueInfo({this.raw, this.units});

  factory ValueInfo.fromJson(Map<String, dynamic> json) => ValueInfo(
        raw: _asDouble(json['raw']),
        units: _asString(json['units']),
      );

  Map<String, dynamic> toJson() => {
        'raw': raw,
        'units': units,
      };
}

/// score {raw, score_10, domain{min,max}, method}
class ScoreInfo {
  final double? raw;
  final double? score10;
  final DomainRange? domain;
  final String? method;

  ScoreInfo({this.raw, this.score10, this.domain, this.method});

  factory ScoreInfo.fromJson(Map<String, dynamic> json) => ScoreInfo(
        raw: _asDouble(json['raw']),
        score10: _asDouble(json['score_10']),
        domain: json['domain'] is Map<String, dynamic> ? DomainRange.fromJson(json['domain']) : null,
        method: _asString(json['method']),
      );

  Map<String, dynamic> toJson() => {
        'raw': raw,
        'score_10': score10,
        'domain': domain?.toJson(),
        'method': method,
      };
}

class DomainRange {
  final double? min;
  final double? max;

  DomainRange({this.min, this.max});

  factory DomainRange.fromJson(Map<String, dynamic> json) => DomainRange(
        min: _asDouble(json['min']),
        max: _asDouble(json['max']),
      );

  Map<String, dynamic> toJson() => {
        'min': min,
        'max': max,
      };
}

/// place {lat,lon,distance_km,distance_note}
class PlaceInfo {
  final double? lat;
  final double? lon;
  final double? distanceKm;
  final String? distanceNote;

  PlaceInfo({this.lat, this.lon, this.distanceKm, this.distanceNote});

  factory PlaceInfo.fromJson(Map<String, dynamic> json) => PlaceInfo(
        lat: _asDouble(json['lat']),
        lon: _asDouble(json['lon']),
        distanceKm: _asDouble(json['distance_km']),
        distanceNote: _asString(json['distance_note']),
      );

  Map<String, dynamic> toJson() => {
        'lat': lat,
        'lon': lon,
        'distance_km': distanceKm,
        'distance_note': distanceNote,
      };
}

/// product meta {z,t,grid_deg,bucket_deg,palette,mode,score_domain_strategy?}
class ProductMeta {
  final int? z;
  final String? t;
  final double? gridDeg;
  final double? bucketDeg;
  final String? palette;
  final String? mode; // "forecast"
  final String? scoreDomainStrategy; // may be null

  ProductMeta({
    this.z,
    this.t,
    this.gridDeg,
    this.bucketDeg,
    this.palette,
    this.mode,
    this.scoreDomainStrategy,
  });

  factory ProductMeta.fromJson(Map<String, dynamic> json) => ProductMeta(
        z: _asInt(json['z']),
        t: _asString(json['t']),
        gridDeg: _asDouble(json['grid_deg']),
        bucketDeg: _asDouble(json['bucket_deg']),
        palette: _asString(json['palette']),
        mode: _asString(json['mode']),
        scoreDomainStrategy: _asString(json['score_domain_strategy']),
      );

  Map<String, dynamic> toJson() => {
        'z': z,
        't': t,
        'grid_deg': gridDeg,
        'bucket_deg': bucketDeg,
        'palette': palette,
        'mode': mode,
        'score_domain_strategy': scoreDomainStrategy,
      };
}

/// per-product debug
class ProductDebug {
  final InternalCall? internalCall;
  final int? cellsCount;

  ProductDebug({this.internalCall, this.cellsCount});

  factory ProductDebug.fromJson(Map<String, dynamic> json) => ProductDebug(
        internalCall: json['internal_call'] is Map<String, dynamic>
            ? InternalCall.fromJson(json['internal_call'])
            : null,
        cellsCount: _asInt(json['cells_count']),
      );

  Map<String, dynamic> toJson() => {
        'internal_call': internalCall?.toJson(),
        'cells_count': cellsCount,
      };
}

class InternalCall {
  final String? path;
  final Map<String, dynamic>? query;

  InternalCall({this.path, this.query});

  factory InternalCall.fromJson(Map<String, dynamic> json) => InternalCall(
        path: _asString(json['path']),
        query: json['query'] is Map<String, dynamic> ? (json['query'] as Map<String, dynamic>) : null,
      );

  Map<String, dynamic> toJson() => {
        'path': path,
        'query': query,
      };
}

/// overall {succeed,status,score_10,score_100,weights,recommended_actions}
class OverallScores {
  final bool succeed;
  final int status;
  final double? score10;
  final int? score100;
  final Map<String, double> weights;
  final RecommendedActions? recommendedActions;
  final String? message; // when succeed=false

  OverallScores({
    required this.succeed,
    required this.status,
    this.score10,
    this.score100,
    required this.weights,
    this.recommendedActions,
    this.message,
  });

  factory OverallScores.fromJson(Map<String, dynamic> json) {
    final weights = <String, double>{};
    if (json['weights'] is Map) {
      (json['weights'] as Map).forEach((k, v) {
        final d = _asDouble(v);
        if (d != null) weights[k.toString()] = d;
      });
    }
    return OverallScores(
      succeed: _asBool(json['succeed']) ?? false,
      status: _asInt(json['status']) ?? 0,
      score10: _asDouble(json['score_10']),
      score100: _asInt(json['score_100']),
      weights: weights,
      recommendedActions: json['recommended_actions'] is Map<String, dynamic>
          ? RecommendedActions.fromJson(json['recommended_actions'])
          : null,
      message: _asString(json['message']),
    );
  }

  Map<String, dynamic> toJson() => {
        'succeed': succeed,
        'status': status,
        'score_10': score10,
        'score_100': score100,
        'weights': weights,
        'recommended_actions': recommendedActions?.toJson(),
        'message': message,
      };
}

class RecommendedActions {
  final String? level; // Low | Moderate | High | Very High
  final String? advice;

  RecommendedActions({this.level, this.advice});

  factory RecommendedActions.fromJson(Map<String, dynamic> json) => RecommendedActions(
        level: _asString(json['level']),
        advice: _asString(json['advice']),
      );

  Map<String, dynamic> toJson() => {
        'level': level,
        'advice': advice,
      };
}

/// health {succeed,status,risks[],explain}
class HealthSection {
  final bool succeed;
  final int status;
  final List<DiseaseRisk> risks;
  final String? explain;

  HealthSection({
    required this.succeed,
    required this.status,
    required this.risks,
    this.explain,
  });

  factory HealthSection.fromJson(Map<String, dynamic> json) {
    final risks = <DiseaseRisk>[];
    if (json['risks'] is List) {
      for (final e in (json['risks'] as List)) {
        if (e is Map<String, dynamic>) {
          risks.add(DiseaseRisk.fromJson(e));
        }
      }
    }
    return HealthSection(
      succeed: _asBool(json['succeed']) ?? false,
      status: _asInt(json['status']) ?? 0,
      risks: risks,
      explain: _asString(json['explain']),
    );
  }

  Map<String, dynamic> toJson() => {
        'succeed': succeed,
        'status': status,
        'risks': risks.map((e) => e.toJson()).toList(),
        'explain': explain,
      };
}

class DiseaseRisk {
  final String? id;
  final String? name;
  final int? risk0to100;
  final String? level; // Very Low..Very High
  final String? note;
  final List<RiskContributor> contributors;

  DiseaseRisk({
    this.id,
    this.name,
    this.risk0to100,
    this.level,
    this.note,
    required this.contributors,
  });

  factory DiseaseRisk.fromJson(Map<String, dynamic> json) {
    final contribs = <RiskContributor>[];
    if (json['contributors'] is List) {
      for (final e in (json['contributors'] as List)) {
        if (e is Map<String, dynamic>) {
          contribs.add(RiskContributor.fromJson(e));
        }
      }
    }
    return DiseaseRisk(
      id: _asString(json['id']),
      name: _asString(json['name']),
      risk0to100: _asInt(json['risk_0_100']),
      level: _asString(json['level']),
      note: _asString(json['note']),
      contributors: contribs,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'risk_0_100': risk0to100,
        'level': level,
        'note': note,
        'contributors': contributors.map((e) => e.toJson()).toList(),
      };
}

class RiskContributor {
  final String? product;
  final double? weight;
  final double? score10;

  RiskContributor({this.product, this.weight, this.score10});

  factory RiskContributor.fromJson(Map<String, dynamic> json) => RiskContributor(
        product: _asString(json['product']),
        weight: _asDouble(json['weight']),
        score10: _asDouble(json['score10']),
      );

  Map<String, dynamic> toJson() => {
        'product': product,
        'weight': weight,
        'score10': score10,
      };
}

/// root-level debug (bbox_deg, z_eff_note, t_note)
class DebugRoot {
  final List<double>? bboxDeg; // [-77.39, 38.55, -76.69, 39.25]
  final String? zEffNote;
  final String? tNote;

  DebugRoot({this.bboxDeg, this.zEffNote, this.tNote});

  factory DebugRoot.fromJson(Map<String, dynamic> json) => DebugRoot(
        bboxDeg: (json['bbox_deg'] is List)
            ? (json['bbox_deg'] as List).map((e) => _asDouble(e) ?? 0.0).toList()
            : null,
        zEffNote: _asString(json['z_eff_note']),
        tNote: _asString(json['t_note']),
      );

  Map<String, dynamic> toJson() => {
        'bbox_deg': bboxDeg,
        'z_eff_note': zEffNote,
        't_note': tNote,
      };
}

// -------------------------------
// Parsing helpers (defensive)
// -------------------------------

String? _asString(dynamic v) {
  if (v == null) return null;
  if (v is String) return v;
  return v.toString();
}

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is double) return v.toInt();
  if (v is String) {
    final p = int.tryParse(v.trim());
    return p;
  }
  return null;
}

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is int) return v.toDouble();
  if (v is String) {
    final s = v.trim();
    // Handles plain + scientific notation (e.g., 4.03e+15)
    return double.tryParse(s);
  }
  return null;
}

bool? _asBool(dynamic v) {
  if (v == null) return null;
  if (v is bool) return v;
  if (v is int) return v != 0;
  if (v is String) {
    final s = v.toLowerCase().trim();
    return s == '1' || s == 'true' || s == 'yes' || s == 'y' || s == 'on';
  }
  return null;
}
