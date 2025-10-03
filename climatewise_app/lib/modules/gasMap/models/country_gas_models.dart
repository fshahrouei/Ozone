// 1) Detailed record for a single country in a specific year.
class CountryGasData {
  final String entity;   // Country name
  final String isoA3;    // ISO 3166-1 alpha-3 code
  final int year;        // Year
  final double n2o;      // Nitrous oxide emissions
  final double ch4;      // Methane emissions
  final double co2;      // Carbon dioxide emissions
  final double total;    // Total emissions
  final int score;       // Server-provided score (display/ranking)
  final String? image;   // Optional flag image URL

  CountryGasData({
    required this.entity,
    required this.isoA3,
    required this.year,
    required this.n2o,
    required this.ch4,
    required this.co2,
    required this.total,
    required this.score,
    this.image,
  });

  /// Creates a [CountryGasData] from a loosely-typed JSON map.
  /// All numeric fields are defensively parsed from `num` or `String`.
  factory CountryGasData.fromJson(Map<String, dynamic> json) {
    return CountryGasData(
      entity: json['entity'] ?? 'Unknown',
      isoA3: json['iso_a3'] ?? 'UNK',
      year: (json['year'] is int)
          ? json['year']
          : int.tryParse(json['year'].toString()) ?? 0,
      n2o: (json['n2o'] is num)
          ? (json['n2o'] as num).toDouble()
          : double.tryParse(json['n2o'].toString()) ?? 0,
      ch4: (json['ch4'] is num)
          ? (json['ch4'] as num).toDouble()
          : double.tryParse(json['ch4'].toString()) ?? 0,
      co2: (json['co2'] is num)
          ? (json['co2'] as num).toDouble()
          : double.tryParse(json['co2'].toString()) ?? 0,
      total: (json['total'] is num)
          ? (json['total'] as num).toDouble()
          : double.tryParse(json['total'].toString()) ?? 0,
      score: json['score'] is int
          ? json['score']
          : int.tryParse(json['score'].toString()) ?? 1,
      image: json['image'], // may be null
    );
  }

  /// Serializes this model back to JSON.
  Map<String, dynamic> toJson() {
    return {
      'entity': entity,
      'iso_a3': isoA3,
      'year': year,
      'n2o': n2o,
      'ch4': ch4,
      'co2': co2,
      'total': total,
      'score': score,
      'image': image,
    };
  }
}

// 2) Data model for each country item in `top_countries` (BarChart/PieChart).
class CountryStatData {
  final String isoA3;  // ISO 3166-1 alpha-3 code
  final String name;   // Country name
  final double value;  // Aggregated emissions/value for charting

  CountryStatData({
    required this.isoA3,
    required this.name,
    required this.value,
  });

  /// Creates a [CountryStatData] from JSON with defensive numeric parsing.
  factory CountryStatData.fromJson(Map<String, dynamic> json) {
    return CountryStatData(
      isoA3: json['iso_a3'] ?? 'UNK',
      name: json['name'] ?? 'Unknown',
      value: (json['value'] is num)
          ? (json['value'] as num).toDouble()
          : double.tryParse(json['value'].toString()) ?? 0,
    );
  }

  /// Serializes this model back to JSON.
  Map<String, dynamic> toJson() {
    return {
      'iso_a3': isoA3,
      'name': name,
      'value': value,
    };
  }
}

// 3) Yearly time-series record for a country (for LineChart and gas mix PieChart).
class CountryYearlyGasData {
  final int year;      // Year
  final double n2o;    // Nitrous oxide emissions
  final double ch4;    // Methane emissions
  final double co2;    // Carbon dioxide emissions
  final double total;  // Total emissions

  CountryYearlyGasData({
    required this.year,
    required this.n2o,
    required this.ch4,
    required this.co2,
    required this.total,
  });

  /// Creates a [CountryYearlyGasData] from JSON with defensive numeric parsing.
  factory CountryYearlyGasData.fromJson(Map<String, dynamic> json) {
    return CountryYearlyGasData(
      year: (json['year'] is int)
          ? json['year']
          : int.tryParse(json['year'].toString()) ?? 0,
      n2o: (json['n2o'] is num)
          ? (json['n2o'] as num).toDouble()
          : double.tryParse(json['n2o'].toString()) ?? 0,
      ch4: (json['ch4'] is num)
          ? (json['ch4'] as num).toDouble()
          : double.tryParse(json['ch4'].toString()) ?? 0,
      co2: (json['co2'] is num)
          ? (json['co2'] as num).toDouble()
          : double.tryParse(json['co2'].toString()) ?? 0,
      total: (json['total'] is num)
          ? (json['total'] as num).toDouble()
          : double.tryParse(json['total'].toString()) ?? 0,
    );
  }

  /// Serializes this model back to JSON.
  Map<String, dynamic> toJson() {
    return {
      'year': year,
      'n2o': n2o,
      'ch4': ch4,
      'co2': co2,
      'total': total,
    };
  }
}
