// lib/core/services/push_navigation_service.dart
import 'dart:async';
import 'dart:convert';

/// Source of the push tap event (for debugging/analytics if needed).
enum PushSource { fcmTap, initialMessage, localTap, unknown }

/// Normalized payload used by the app when a notification is tapped.
class PushMessage {
  final String? title;
  final String? body;
  final Map<String, dynamic> data;
  final DateTime receivedAt;
  final PushSource source;

  const PushMessage({
    this.title,
    this.body,
    this.data = const {},
    required this.receivedAt,
    this.source = PushSource.unknown,
  });

  /// Convenience getters for common keys (customize to your backend contract).
  String? get id => _stringOrNull(data['id']);
  String? get type => _stringOrNull(data['type']);
  String? get route => _stringOrNull(data['route']) ?? _stringOrNull(data['deeplink']);

  static String? _stringOrNull(Object? v) => v is String && v.isNotEmpty ? v : null;

  @override
  String toString() => 'PushMessage(title=$title, body=$body, data=$data, source=$source)';
}

/// A tiny singleton service to:
/// 1) Keep the last tapped push (pending) until UI consumes it
/// 2) Notify listeners (MainNavigation) to show a dialog/sheet
/// 3) Provide a simple API for setting from FCM or local notifications
///
/// Usage:
///   PushNavigationService.I.setFromFcmTap(title: ..., body: ..., data: ...);
///   // In MainNavigation (initState):
///   final sub = PushNavigationService.I.stream.listen((_) => _maybeShowDialog());
///   final pending = PushNavigationService.I.takePending(); // null-safety checked
class PushNavigationService {
  PushNavigationService._();
  static final PushNavigationService I = PushNavigationService._();

  PushMessage? _pending;

  /// Broadcast stream to notify UI that a new pending message arrived.
  final StreamController<PushMessage> _controller = StreamController.broadcast();

  /// Listen to be notified when a push tap is received.
  Stream<PushMessage> get stream => _controller.stream;

  /// Returns the current pending message (if any) without clearing it.
  PushMessage? peek() => _pending;

  /// Returns and clears the current pending message (one-shot consumption).
  PushMessage? takePending() {
    final m = _pending;
    _pending = null;
    return m;
  }

  /// Sets a pending message and notifies listeners.
  void _setPendingInternal(PushMessage msg) {
    _pending = msg;
    // Notify after a short microtask to ensure UI has built.
    scheduleMicrotask(() => _controller.add(msg));
  }

  /// Public API: set from raw fields (use this in main.dart after FCM tap handlers).
  void setPending({
    String? title,
    String? body,
    Map<String, dynamic>? data,
    PushSource source = PushSource.unknown,
    DateTime? receivedAt,
  }) {
    _setPendingInternal(PushMessage(
      title: title,
      body: body,
      data: _normalizeDataMap(data),
      source: source,
      receivedAt: receivedAt ?? DateTime.now(),
    ));
  }

  /// Parse payload coming from a local notification click (string payload).
  /// Accepts JSON map as string or key=value&key2=value2 formats.
  void setFromLocalTapPayload(String? payload) {
    final Map<String, dynamic> data = _parseArbitraryPayload(payload);
    setPending(
      title: _stringOrNull(data['title']),
      body: _stringOrNull(data['body']),
      data: data,
      source: PushSource.localTap,
    );
  }

  /// Helper: parse JSON or querystring-like payload into a map.
  Map<String, dynamic> _parseArbitraryPayload(String? payload) {
    if (payload == null || payload.trim().isEmpty) return {};
    final raw = payload.trim();

    // Try JSON first
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return decoded.map((k, v) => MapEntry('$k', v));
    } catch (_) {
      // fallthrough
    }

    // Try querystring-ish: key=a&b=c
    if (raw.contains('=') && raw.contains('&')) {
      final Map<String, dynamic> map = {};
      for (final pair in raw.split('&')) {
        final i = pair.indexOf('=');
        if (i <= 0) continue;
        final k = pair.substring(0, i);
        final v = pair.substring(i + 1);
        map[k] = Uri.decodeComponent(v);
      }
      return map;
    }

    // Fallback as plain body
    return {'body': raw};
  }

  /// Normalizes possibly-null or non-string-key maps.
  static Map<String, dynamic> _normalizeDataMap(Map<String, dynamic>? input) {
    if (input == null) return const {};
    final out = <String, dynamic>{};
    input.forEach((k, v) => out['$k'] = v);
    return out;
  }

  static String? _stringOrNull(Object? v) => v is String && v.isNotEmpty ? v : null;

  /// Dispose when app closes (usually not needed in a long-lived singleton).
  void dispose() {
    _controller.close();
  }
}
