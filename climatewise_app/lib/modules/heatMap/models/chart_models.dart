/// Data model representing the top 10 countries (based on anomaly and temperature).
class HeatCountryStat {
  final String isoA3;
  final String name;
  final double tas;
  final double anomaly;

  HeatCountryStat({
    required this.isoA3,
    required this.name,
    required this.tas,
    required this.anomaly,
  });

  /// Creates a [HeatCountryStat] instance from a JSON map.
  factory HeatCountryStat.fromJson(Map<String, dynamic> json) {
    return HeatCountryStat(
      isoA3: json['iso_a3'] ?? '',
      name: json['name'] ?? '',
      tas: (json['tas'] ?? 0).toDouble(),
      anomaly: (json['anomaly'] ?? 0).toDouble(),
    );
  }
}

/// Data model representing global trend values per year (trend array).
class HeatTrendYear {
  final int year;
  final double tas;
  final double anomaly;

  HeatTrendYear({
    required this.year,
    required this.tas,
    required this.anomaly,
  });

  /// Creates a [HeatTrendYear] instance from a list array.
  /// Expected format: [year, tas, anomaly].
  factory HeatTrendYear.fromJson(List<dynamic> arr) {
    return HeatTrendYear(
      year: arr[0],
      tas: arr[1].toDouble(),
      anomaly: arr[2].toDouble(),
    );
  }
}

/// Data model representing the global average for the selected year.
class GlobalAverage {
  final double tas;
  final double anomaly;

  GlobalAverage({required this.tas, required this.anomaly});

  /// Creates a [GlobalAverage] instance from a JSON map.
  factory GlobalAverage.fromJson(Map<String, dynamic> json) {
    return GlobalAverage(
      tas: (json['tas'] ?? 0).toDouble(),
      anomaly: (json['anomaly'] ?? 0).toDouble(),
    );
  }
}
