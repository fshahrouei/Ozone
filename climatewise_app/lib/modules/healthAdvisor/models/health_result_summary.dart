// lib/modules/healthAdvisor/models/health_result_summary.dart
// Model for HealthAdvisor saved records (card-friendly).
// Matches API: GET /api/v1/frontend/health-advisor/index (items)
// and POST /api/v1/frontend/health-advisor/store (data)

import 'package:flutter/foundation.dart';

/// Client sensitivity preset
enum Sensitivity { sensitive, normal, relaxed }

Sensitivity _sensitivityFromString(String? s) {
  switch ((s ?? '').toLowerCase().trim()) {
    case 'sensitive':
      return Sensitivity.sensitive;
    case 'relaxed':
      return Sensitivity.relaxed;
    default:
      return Sensitivity.normal;
  }
}

String _sensitivityToString(Sensitivity s) {
  switch (s) {
    case Sensitivity.sensitive:
      return 'sensitive';
    case Sensitivity.relaxed:
      return 'relaxed';
    case Sensitivity.normal:
      return 'normal';
  }
}

/// Alerts payload: { pollution: bool, sound: bool, hours2h: [int,int,...] }
@immutable
class HealthAlerts {
  final bool pollution;
  final bool sound;
  final List<int> hours2h;

  const HealthAlerts({
    required this.pollution,
    required this.sound,
    required this.hours2h,
  });

  factory HealthAlerts.fromJson(Map<String, dynamic>? json) {
    final j = json ?? const {};
    final rawHours = (j['hours2h'] is List) ? (j['hours2h'] as List) : const [];
    return HealthAlerts(
      pollution: (j['pollution'] ?? false) == true,
      sound: (j['sound'] ?? true) == true,
      hours2h: rawHours.map((e) => int.tryParse('$e') ?? 0).toSet().toList()..sort(),
    );
  }

  Map<String, dynamic> toJson() => {
        'pollution': pollution,
        'sound': sound,
        'hours2h': hours2h,
      };

  HealthAlerts copyWith({
    bool? pollution,
    bool? sound,
    List<int>? hours2h,
  }) {
    return HealthAlerts(
      pollution: pollution ?? this.pollution,
      sound: sound ?? this.sound,
      hours2h: List<int>.from(hours2h ?? this.hours2h),
    );
  }

  @override
  String toString() => 'HealthAlerts(pollution=$pollution, sound=$sound, hours2h=$hours2h)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HealthAlerts &&
          runtimeType == other.runtimeType &&
          pollution == other.pollution &&
          sound == other.sound &&
          listEquals(hours2h, other.hours2h);

  @override
  int get hashCode => Object.hash(pollution, sound, Object.hashAll(hours2h));
}

/// Location holder for (lat, lon)
@immutable
class GeoPoint {
  final double? lat;
  final double? lon;

  const GeoPoint({this.lat, this.lon});

  factory GeoPoint.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const GeoPoint(lat: null, lon: null);
    final lat = json['lat'];
    final lon = json['lon'];
    return GeoPoint(
      lat: (lat is num) ? lat.toDouble() : double.tryParse('$lat'),
      lon: (lon is num) ? lon.toDouble() : double.tryParse('$lon'),
    );
  }

  Map<String, dynamic> toJson() => {'lat': lat, 'lon': lon};

  @override
  String toString() => 'GeoPoint(lat=$lat, lon=$lon)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GeoPoint && runtimeType == other.runtimeType && lat == other.lat && lon == other.lon;

  @override
  int get hashCode => Object.hash(lat, lon);
}

/// Main model used by the "Saved points" tab
@immutable
class HealthResultSummary {
  final int? id; // present in index/store response
  final String uuid;
  final String name;
  final GeoPoint location;
  final Sensitivity sensitivity;
  final int overallScore; // 0..100
  final List<String> diseases;
  final HealthAlerts alerts;
  final DateTime? receivedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const HealthResultSummary({
    required this.id,
    required this.uuid,
    required this.name,
    required this.location,
    required this.sensitivity,
    required this.overallScore,
    required this.diseases,
    required this.alerts,
    this.receivedAt,
    this.createdAt,
    this.updatedAt,
  });

  /// Build from API item (index/store 'data' or 'items' element)
  factory HealthResultSummary.fromJson(Map<String, dynamic> json) {
    // API returns location as {lat, lon} or nulls; alerts as object
    final diseasesRaw = (json['diseases'] is List) ? (json['diseases'] as List) : const [];
    final diseases = diseasesRaw.map((e) => ('$e').toLowerCase().trim()).where((e) => e.isNotEmpty).toList();

    // Timestamps (ISO8601 or null)
    DateTime? _dt(dynamic v) => (v == null || '$v'.isEmpty) ? null : DateTime.tryParse('$v');

    return HealthResultSummary(
      id: (json['id'] == null) ? null : int.tryParse('${json['id']}'),
      uuid: '${json['uuid'] ?? ''}',
      name: '${json['name'] ?? ''}',
      location: GeoPoint.fromJson(json['location'] as Map<String, dynamic>?),
      sensitivity: _sensitivityFromString(json['sensitivity'] as String?),
      overallScore: int.tryParse('${json['overall_score'] ?? 0}')?.clamp(0, 100) ?? 0,
      diseases: diseases,
      alerts: HealthAlerts.fromJson(json['alerts'] as Map<String, dynamic>?),
      receivedAt: _dt(json['received_at']),
      createdAt: _dt(json['created_at']),
      updatedAt: _dt(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'uuid': uuid,
        'name': name,
        'location': location.toJson(),
        'sensitivity': _sensitivityToString(sensitivity),
        'overall_score': overallScore,
        'diseases': diseases,
        'alerts': alerts.toJson(),
        'received_at': receivedAt?.toIso8601String(),
        'created_at': createdAt?.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
      };

  HealthResultSummary copyWith({
    int? id,
    String? uuid,
    String? name,
    GeoPoint? location,
    Sensitivity? sensitivity,
    int? overallScore,
    List<String>? diseases,
    HealthAlerts? alerts,
    DateTime? receivedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return HealthResultSummary(
      id: id ?? this.id,
      uuid: uuid ?? this.uuid,
      name: name ?? this.name,
      location: location ?? this.location,
      sensitivity: sensitivity ?? this.sensitivity,
      overallScore: overallScore ?? this.overallScore,
      diseases: diseases ?? List<String>.from(this.diseases),
      alerts: alerts ?? this.alerts,
      receivedAt: receivedAt ?? this.receivedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Convenience: map 0..100 to a compact level used in cards
  String get levelLabel {
    final s = overallScore;
    if (s >= 85) return 'Very High';
    if (s >= 65) return 'High';
    if (s >= 40) return 'Moderate';
    if (s >= 20) return 'Low';
    return 'Very Low';
  }

  /// Convenience: shows "(lat, lon)" or "No location"
  String get locationLabel {
    final lat = location.lat;
    final lon = location.lon;
    return (lat == null || lon == null) ? 'No location' : '(${lat.toStringAsFixed(4)}, ${lon.toStringAsFixed(4)})';
  }

  @override
  String toString() =>
      'HealthResultSummary(id=$id, uuid=$uuid, name=$name, score=$overallScore, sensitivity=$sensitivity)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HealthResultSummary &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          uuid == other.uuid &&
          name == other.name &&
          location == other.location &&
          sensitivity == other.sensitivity &&
          overallScore == other.overallScore &&
          listEquals(diseases, other.diseases) &&
          alerts == other.alerts &&
          receivedAt == other.receivedAt &&
          createdAt == other.createdAt &&
          updatedAt == other.updatedAt;

  @override
  int get hashCode => Object.hash(
        id,
        uuid,
        name,
        location,
        sensitivity,
        overallScore,
        Object.hashAll(diseases),
        alerts,
        receivedAt,
        createdAt,
        updatedAt,
      );

  // ---------- Helpers for list parsing ----------

  /// Parse list from index response: { data: [ ...items ], meta: { ... } }
  static List<HealthResultSummary> listFromIndexResponse(Map<String, dynamic> json) {
    final data = (json['data'] is List) ? (json['data'] as List) : const [];
    return data
        .whereType<Map<String, dynamic>>()
        .map((m) => HealthResultSummary.fromJson(m))
        .toList(growable: false);
    }

  /// Parse single record from store response: { data: { ...item } }
  static HealthResultSummary? fromStoreResponse(Map<String, dynamic> json) {
    final m = (json['data'] is Map) ? (json['data'] as Map) : null;
    if (m == null) return null;
    return HealthResultSummary.fromJson(Map<String, dynamic>.from(m as Map));
  }
}
