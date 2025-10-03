// lib/modules/healthAdvisor/models/health_form.dart
import 'package:latlong2/latlong.dart';

/// Represents the health form data that will be sent to the server.
class HealthForm {
  /// Optional app-specific identifier to correlate submissions (guest/user id).
  /// Will be sent as `client_id` when provided.
  final String? clientId;

  final String name;
  final LatLng location;
  final String sensitivity; // "sensitive" | "normal" | "relaxed"
  final List<String> diseases; // selected disease IDs
  final int overallScore; // 0..100
  final Alerts alerts;

  HealthForm({
    this.clientId,
    required this.name,
    required this.location,
    required this.sensitivity,
    required this.diseases,
    required this.overallScore,
    required this.alerts,
  });

  /// Convert model to JSON for API submission
  Map<String, dynamic> toJson() {
    return {
      if (clientId != null && clientId!.trim().isNotEmpty) 'client_id': clientId,
      'name': name,
      'location': {
        'lat': location.latitude,
        'lon': location.longitude,
      },
      'sensitivity': sensitivity,
      'diseases': diseases,
      'overall_score': overallScore,
      'alerts': alerts.toJson(),
    };
  }

  /// Factory to create from JSON (if needed later)
  factory HealthForm.fromJson(Map<String, dynamic> json) {
    return HealthForm(
      clientId: json['client_id'] as String?,
      name: (json['name'] ?? '') as String,
      location: LatLng(
        (json['location']?['lat'] as num).toDouble(),
        (json['location']?['lon'] as num).toDouble(),
      ),
      sensitivity: (json['sensitivity'] ?? 'normal') as String,
      diseases: List<String>.from(json['diseases'] ?? const []),
      overallScore: (json['overall_score'] as num?)?.toInt() ?? 0,
      alerts: Alerts.fromJson(json['alerts'] ?? const {}),
    );
  }

  /// Handy copyWith for UI/controller adjustments
  HealthForm copyWith({
    String? clientId,
    String? name,
    LatLng? location,
    String? sensitivity,
    List<String>? diseases,
    int? overallScore,
    Alerts? alerts,
  }) {
    return HealthForm(
      clientId: clientId ?? this.clientId,
      name: name ?? this.name,
      location: location ?? this.location,
      sensitivity: sensitivity ?? this.sensitivity,
      diseases: diseases ?? this.diseases,
      overallScore: overallScore ?? this.overallScore,
      alerts: alerts ?? this.alerts,
    );
  }
}

/// Alerts info (notifications, sound, selected hours)
class Alerts {
  final bool pollution;
  final bool sound;
  final List<int> hours2h; // [0,2,4...]

  Alerts({
    required this.pollution,
    required this.sound,
    required this.hours2h,
  });

  Map<String, dynamic> toJson() {
    return {
      'pollution': pollution,
      'sound': sound,
      'hours2h': hours2h,
    };
  }

  factory Alerts.fromJson(Map<String, dynamic> json) {
    return Alerts(
      pollution: (json['pollution'] ?? false) as bool,
      sound: (json['sound'] ?? true) as bool,
      hours2h: List<int>.from(json['hours2h'] ?? const []),
    );
  }

  Alerts copyWith({
    bool? pollution,
    bool? sound,
    List<int>? hours2h,
  }) {
    return Alerts(
      pollution: pollution ?? this.pollution,
      sound: sound ?? this.sound,
      hours2h: hours2h ?? this.hours2h,
    );
  }
}
