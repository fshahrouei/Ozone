import 'dart:convert';

/// A single timeline item for forecast data (future).
class ForecastSlot {
  /// Forecast offset in hours (+1h .. +12h).
  final int offsetHours;

  /// Start time of the forecast interval (UTC).
  final DateTime t0;

  /// End time of the forecast interval (UTC).
  final DateTime t1;

  /// Always `true` to distinguish forecast items in the UI.
  final bool isForecast;

  const ForecastSlot({
    required this.offsetHours,
    required this.t0,
    required this.t1,
    this.isForecast = true,
  });

  /// Factory constructor from a map (expected schema):
  /// `{ offset: 1, start: "ISO", end: "ISO" }`
  factory ForecastSlot.fromMap(Map<String, dynamic> m) {
    final offset = int.tryParse(m['offset'].toString()) ?? -1;
    final t0 = _parseIsoToUtc(m['start']);
    final t1 = _parseIsoToUtc(m['end']);
    if (offset < 0) {
      throw FormatException('Invalid ForecastSlot offset: $m');
    }
    return ForecastSlot(offsetHours: offset, t0: t0, t1: t1);
  }

  /// Create a list of `ForecastSlot` objects from a raw JSON-like list.
  static List<ForecastSlot> listFromItems(dynamic items) {
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map<Map<String, dynamic>>((e) => e.cast<String, dynamic>())
        .map(ForecastSlot.fromMap)
        .toList();
  }

  /// Convert to a simple map for serialization.
  Map<String, dynamic> toMap() => {
        'offset': offsetHours,
        't0': t0.toIso8601String(),
        't1': t1.toIso8601String(),
      };

  /// Convert to JSON string.
  String toJson() => jsonEncode(toMap());

  /// Display label in +Nh format.
  String get label => '+${offsetHours}h';

  /// Display label with local time (HH:mm).
  String get labelLocal => _fmtHHmm(t1.toLocal());

  /// Unique key for UI identification.
  String get key => 'forecast+$offsetHours@${t1.toIso8601String()}';

  @override
  String toString() => 'ForecastSlot(+${offsetHours}h @ ${t1.toIso8601String()})';

  @override
  bool operator ==(Object other) {
    return other is ForecastSlot &&
        other.offsetHours == offsetHours &&
        other.t1 == t1;
  }

  @override
  int get hashCode => Object.hash(offsetHours, t1);

  // ------- helpers -------

  /// Parse an ISO8601 string (or dynamic value) to UTC DateTime.
  static DateTime _parseIsoToUtc(dynamic v) {
    final s = v?.toString().trim();
    if (s == null || s.isEmpty) {
      throw FormatException('Cannot parse ISO8601 time: $v');
    }
    final dt = DateTime.tryParse(s);
    if (dt == null) throw FormatException('Invalid date: $v');
    return dt.toUtc();
  }

  /// Format a DateTime object into HH:mm string.
  static String _fmtHHmm(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
