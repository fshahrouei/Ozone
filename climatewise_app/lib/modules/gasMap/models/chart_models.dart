class GasStatData {
  final String isoA3;
  final String name;
  final double value;

  GasStatData({
    required this.isoA3,
    required this.name,
    required this.value,
  });

  factory GasStatData.fromJson(Map<String, dynamic> json) {
    return GasStatData(
      isoA3: json['iso_a3'] ?? '',
      name: json['name'] ?? '',
      value: (json['value'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'iso_a3': isoA3,
      'name': name,
      'value': value,
    };
  }
}



class GasYearValue {
  final int year;
  final double value;

  GasYearValue({
    required this.year,
    required this.value,
  });

  factory GasYearValue.fromJson(Map<String, dynamic> json) {
    return GasYearValue(
      year: json['year'] ?? 0,
      value: (json['value'] ?? 0).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'year': year,
      'value': value,
    };
  }
}

class GasHistoryData {
  final String isoA3;
  final String name;
  final List<GasYearValue> values;

  GasHistoryData({
    required this.isoA3,
    required this.name,
    required this.values,
  });

  factory GasHistoryData.fromJson(Map<String, dynamic> json) {
    return GasHistoryData(
      isoA3: json['iso_a3'] ?? '',
      name: json['name'] ?? '',
      values: (json['values'] as List<dynamic>?)
              ?.map((e) => GasYearValue.fromJson(e as Map<String, dynamic>)).toList() ?? [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'iso_a3': isoA3,
      'name': name,
      'values': values.map((e) => e.toJson()).toList(),
    };
  }
}
