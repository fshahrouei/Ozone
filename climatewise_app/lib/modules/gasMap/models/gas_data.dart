class GasData {
  final String isoA3;
  final String total;
  final int score;

  GasData({
    required this.isoA3,
    required this.total,
    required this.score,
  });

  factory GasData.fromJson(Map<String, dynamic> json) {
    return GasData(
      isoA3: json['iso_a3'] ?? 'Unknown',
      total: json['total'] ?? '0',
      score: json['score'] != null ? json['score'] as int : 1,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'iso_a3': isoA3,
      'total': total,
      'score': score,
    };
  }
}
