// lib/modules/aqMap/models/app_status.dart

class AppStatus {
  final bool succeed;
  final int status;
  final String product;
  final String units;

  final String? latestGid;
  final DateTime? latestStart;
  final DateTime? latestEnd;

  final String? tempoGid;

  final DateTime nowUtc;
  final String? t;        // e.g. "+3" or "now"
  final int z;            // zoom bucket
  final String mode;      // "real" | "forecast"
  final DateTime frameUtc;

  final int clockMin;     // always positive, direction from mode

  final List<String> sources;
  final DateTime? runGeneratedUtc;

  final int? tempoAgeMin;
  final bool tempoLive;

  final bool? isDay;
  final String? message;

  AppStatus({
    required this.succeed,
    required this.status,
    required this.product,
    required this.units,
    this.latestGid,
    this.latestStart,
    this.latestEnd,
    this.tempoGid,
    required this.nowUtc,
    this.t,
    required this.z,
    required this.mode,
    required this.frameUtc,
    required this.clockMin,
    required this.sources,
    this.runGeneratedUtc,
    this.tempoAgeMin,
    required this.tempoLive,
    this.isDay,
    this.message,
  });

  factory AppStatus.fromJson(Map<String, dynamic> json) {
    final latest = json['latest'] as Map<String, dynamic>?;
    return AppStatus(
      succeed: json['succeed'] ?? false,
      status: json['status'] ?? 0,
      product: json['product'] ?? '',
      units: json['units'] ?? '',
      latestGid: latest?['gid'],
      latestStart: latest?['start'] != null ? DateTime.parse(latest!['start']) : null,
      latestEnd: latest?['end'] != null ? DateTime.parse(latest!['end']) : null,
      tempoGid: json['tempo_gid'],
      nowUtc: DateTime.parse(json['now_utc']),
      t: json['t'],
      z: json['z'] ?? 0,
      mode: json['mode'] ?? '',
      frameUtc: DateTime.parse(json['frame_utc']),
      clockMin: json['clock_min'] ?? 0,
      sources: (json['sources'] as List<dynamic>? ?? []).map((e) => e.toString()).toList(),
      runGeneratedUtc: json['run_generated_utc'] != null
          ? DateTime.parse(json['run_generated_utc'])
          : null,
      tempoAgeMin: json['tempo_age_min'],
      tempoLive: json['tempo_live'] ?? false,
      isDay: json['is_day'],
      message: json['message'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'succeed': succeed,
      'status': status,
      'product': product,
      'units': units,
      'latest': latestGid != null
          ? {
              'gid': latestGid,
              'start': latestStart?.toIso8601String(),
              'end': latestEnd?.toIso8601String(),
            }
          : null,
      'tempo_gid': tempoGid,
      'now_utc': nowUtc.toIso8601String(),
      't': t,
      'z': z,
      'mode': mode,
      'frame_utc': frameUtc.toIso8601String(),
      'clock_min': clockMin,
      'sources': sources,
      'run_generated_utc': runGeneratedUtc?.toIso8601String(),
      'tempo_age_min': tempoAgeMin,
      'tempo_live': tempoLive,
      'is_day': isDay,
      'message': message,
    };
  }
}
