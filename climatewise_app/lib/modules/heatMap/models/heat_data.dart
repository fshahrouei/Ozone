/// Data model representing heat information for a specific country.
class HeatData {
  /// ISO Alpha-3 country code (e.g., "USA", "IRN").
  final String isoA3;

  /// Mean surface air temperature (°C).
  final double tas;

  /// Temperature anomaly compared to baseline (°C).
  final double anomaly;

  /// Color score used for visualization (1 to 10).
  final int score;

  HeatData({
    required this.isoA3,
    required this.tas,
    required this.anomaly,
    required this.score,
  });

  /// Creates a [HeatData] instance from a JSON map.
  factory HeatData.fromJson(Map<String, dynamic> json) {
    return HeatData(
      isoA3: json['iso_a3'] ?? 'Unknown',
      tas: (json['tas'] is num)
          ? (json['tas'] as num).toDouble()
          : double.tryParse(json['tas'].toString()) ?? 0,
      anomaly: (json['anomaly'] is num)
          ? (json['anomaly'] as num).toDouble()
          : double.tryParse(json['anomaly'].toString()) ?? 0,
      score: json['score'] is int
          ? json['score']
          : int.tryParse(json['score'].toString()) ?? 1,
    );
  }

  /// Converts this [HeatData] instance to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'iso_a3': isoA3,
      'tas': tas,
      'anomaly': anomaly,
      'score': score,
    };
  }
}
