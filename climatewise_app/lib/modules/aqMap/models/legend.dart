import 'package:flutter/material.dart';

class Legend {
  final bool succeed;
  final int status;
  final String product;
  final String units;
  final String palette;
  final List<double> stops;
  final List<double> values;
  final List<String> labels;
  final List<Color> colors;
  final String? message;

  const Legend({
    required this.succeed,
    required this.status,
    required this.product,
    required this.units,
    required this.palette,
    required this.stops,
    required this.values,
    required this.labels,
    required this.colors,
    this.message,
  });

  factory Legend.fromMap(Map<String, dynamic> map) {
    return Legend(
      succeed: map['succeed'] == true,
      status: (map['status'] as num?)?.toInt() ?? 0,
      product: (map['product'] as String?) ?? '',
      units: (map['units'] as String?) ?? '',
      palette: (map['palette'] as String?) ?? '',
      stops: (map['stops'] as List?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          const [],
      values: (map['values'] as List?)
              ?.map((e) => (e as num).toDouble())
              .toList() ??
          const [],
      labels: (map['labels'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      colors: (map['colors'] as List?)
              ?.map((e) => _parseHexColor(e.toString()))
              .toList() ??
          const [],
      message: map['message'] as String?,
    );
  }

  static Color _parseHexColor(String hex) {
    final buffer = StringBuffer();
    if (hex.length == 6 || hex.length == 7) buffer.write('ff');
    buffer.write(hex.replaceFirst('#', ''));
    return Color(int.parse(buffer.toString(), radix: 16));
  }
}
