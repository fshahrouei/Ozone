// lib/modules/aqMap/models/overlay_slot.dart
//
// Overlay Slot model – timeline items for TEMPO at zoom level 3.
// Each item represents a granule (gid) with a start and end timestamp (UTC).
// Self-contained: no external dependencies (like intl); provides simple
// built-in display formatting utilities.
//
// Author: you 🫶

import 'dart:convert';

/// A single timeline slot (granule).
class OverlaySlot {
  /// Granule identifier (e.g., `G3683552335-LARC_CLOUD`).
  final String gid;

  /// Start of the time window (UTC) — in new API: `start`.
  final DateTime t0;

  /// End of the time window / primary display timestamp (UTC) — in new API: `end`.
  final DateTime t1;

  /// Saved timestamp (UTC) on disk – optional (may be missing in new responses).
  final DateTime? saved;

  const OverlaySlot({
    required this.gid,
    required this.t0,
    required this.t1,
    this.saved,
  });

  /// Build from server response map (new schema):
  /// `{ gid: "...", start: "ISO", end: "ISO", saved?: "ISO" }`
  factory OverlaySlot.fromMap(Map<String, dynamic> m) {
    final gid = (m['gid'] ?? '').toString().trim();

    final t0 = _parseIsoToUtc(m['start']);
    final t1 = _parseIsoToUtc(m['end']);

    // `saved` is optional; parse if present.
    final saved = _tryParseIsoToUtc(m['saved']);

    if (gid.isEmpty) {
      throw FormatException('Invalid OverlaySlot map: $m');
    }

    return OverlaySlot(gid: gid, t0: t0, t1: t1, saved: saved);
  }

  /// Build a list from `times` array in overlay-times response.
  static List<OverlaySlot> listFromItems(dynamic items) {
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map<Map<String, dynamic>>((e) => e.cast<String, dynamic>())
        .map(OverlaySlot.fromMap)
        .toList();
  }

  /// Convert to map (for debugging or caching).
  Map<String, dynamic> toMap() => {
        'gid': gid,
        // Keep output keys as t0/t1 for compatibility with existing code.
        't0': t0.toIso8601String(),
        't1': t1.toIso8601String(),
        if (saved != null) 'saved': saved!.toIso8601String(),
      };

  /// Convert to JSON (for debugging).
  String toJson() => jsonEncode(toMap());

  /// Local time label (HH:mm) for button display.
  String get labelLocal => _fmtHHmm(t1.toLocal());

  /// Local day key (yyyy-MM-dd) for grouping/dividers.
  String get dayKeyLocal {
    final d = t1.toLocal();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }

  /// Short date label (e.g., `Sep 1`) without intl dependency.
  String get shortDateLabelLocal {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    final d = t1.toLocal();
    final name = months[(d.month - 1).clamp(0, 11)];
    return '$name ${d.day}';
  }

  /// Compare by `t1` (for sorting).
  int compareByT1(OverlaySlot other) => t1.compareTo(other.t1);

  /// Check if two slots are in the same local day.
  bool isSameLocalDay(OverlaySlot other) => dayKeyLocal == other.dayKeyLocal;

  /// Unique key for UI (e.g., for use in `ListView.builder`).
  String get key => '$gid@${t1.toIso8601String()}';

  @override
  String toString() => 'OverlaySlot($gid @ ${t1.toIso8601String()})';

  @override
  bool operator ==(Object other) {
    return other is OverlaySlot && other.gid == gid && other.t1 == t1;
  }

  @override
  int get hashCode => Object.hash(gid, t1);

  // ------- private helpers -------

  /// Attempt to parse an ISO8601 timestamp to UTC DateTime, return null if invalid.
  static DateTime? _tryParseIsoToUtc(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;
    final dt = DateTime.tryParse(s);
    return dt?.toUtc();
  }

  /// Parse an ISO8601 timestamp to UTC DateTime, throw on failure.
  static DateTime _parseIsoToUtc(dynamic v) {
    final dt = _tryParseIsoToUtc(v);
    if (dt == null) {
      throw FormatException('Cannot parse ISO8601 time: $v');
    }
    return dt;
  }

  /// Format a DateTime as HH:mm string.
  static String _fmtHHmm(DateTime d) {
    final h = d.hour.toString().padLeft(2, '0');
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
}
