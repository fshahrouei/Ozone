/// Data model representing summary information of a country for a specific year.
class CountryHeatData {
  final String entity;
  final String isoA3;
  final double tas;
  final double anomaly;
  final String? flag;

  CountryHeatData({
    required this.entity,
    required this.isoA3,
    required this.tas,
    required this.anomaly,
    this.flag,
  });

  /// Creates a [CountryHeatData] instance from a JSON map.
  factory CountryHeatData.fromJson(Map<String, dynamic> json) {
    return CountryHeatData(
      entity: json['entity'] ?? 'Unknown',
      isoA3: json['iso_a3'] ?? 'UNK',
      tas: (json['tas'] ?? 0).toDouble(),
      anomaly: (json['anomaly'] ?? 0).toDouble(),
      flag: json['flag'],
    );
  }

  /// Converts this [CountryHeatData] instance to JSON map.
  Map<String, dynamic> toJson() {
    return {
      'entity': entity,
      'iso_a3': isoA3,
      'tas': tas,
      'anomaly': anomaly,
      'flag': flag,
    };
  }
}

/// Data model representing each country in the comparative list (bar_compare).
class CompareCountryData {
  final String isoA3;
  final String country;
  final double tas;
  final double anomaly;
  final String? flag;

  CompareCountryData({
    required this.isoA3,
    required this.country,
    required this.tas,
    required this.anomaly,
    this.flag,
  });

  /// Creates a [CompareCountryData] instance from a JSON map.
  factory CompareCountryData.fromJson(Map<String, dynamic> json) {
    return CompareCountryData(
      isoA3: json['iso_a3'] ?? '',
      country: json['country'] ?? '',
      tas: (json['tas'] ?? 0).toDouble(),
      anomaly: (json['anomaly'] ?? 0).toDouble(),
      flag: json['flag'],
    );
  }
}

/// Data model representing yearly heat data for a country (used in line charts).
class CountryYearlyHeatData {
  final int year;
  final double tas;
  final double anomaly;

  CountryYearlyHeatData({
    required this.year,
    required this.tas,
    required this.anomaly,
  });

  /// Creates a [CountryYearlyHeatData] instance from a JSON map.
  factory CountryYearlyHeatData.fromJson(Map<String, dynamic> json) {
    return CountryYearlyHeatData(
      year: (json['year'] is int)
          ? json['year']
          : int.tryParse(json['year'].toString()) ?? 0,
      tas: (json['tas'] ?? 0).toDouble(),
      anomaly: (json['anomaly'] ?? 0).toDouble(),
    );
  }
}
