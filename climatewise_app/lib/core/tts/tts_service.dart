// lib/core/tts/tts_service.dart
// Lightweight on-device TTS service. Handles init, speak, stop, simple state.

import 'dart:io';
import 'package:flutter_tts/flutter_tts.dart';

class TtsService {
  TtsService._();
  static final TtsService instance = TtsService._();

  final FlutterTts _tts = FlutterTts();

  bool _initialized = false;
  bool _speaking = false;

  bool get isInitialized => _initialized;
  bool get isSpeaking => _speaking;

  /// Initialize engine with reasonable defaults. Call once on app start.
  Future<void> init({
    String language = 'fa-IR',
    double rate = 0.45,  // 0.0 .. 1.0
    double pitch = 1.0,  // 0.5 .. 2.0
    double volume = 1.0, // 0.0 .. 1.0
  }) async {
    if (_initialized) return;

    // iOS: allow mix/duck so other audio (e.g., music) lowers volume instead of stopping.
    if (Platform.isIOS) {
      await _tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.playback,
        [
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          IosTextToSpeechAudioCategoryOptions.duckOthers,
        ],
        IosTextToSpeechAudioMode.defaultMode,
      );
    }

    await _tts.setLanguage(language);
    await _tts.setSpeechRate(rate);
    await _tts.setPitch(pitch);
    await _tts.setVolume(volume);

    // Await completion so we can sequence or interrupt properly.
    await _tts.awaitSpeakCompletion(true);

    // Event handlers
    _tts.setStartHandler(() => _speaking = true);
    _tts.setCompletionHandler(() => _speaking = false);
    _tts.setCancelHandler(() => _speaking = false);
    _tts.setErrorHandler((msg) {
      _speaking = false;
      // You may log errors here if you have a logger.
    });

    _initialized = true;
  }

  /// Speak a text. If [interrupt] is true, stop any ongoing speech first.
  Future<void> speak(String text, {bool interrupt = true}) async {
    final String trimmed = text.trim();
    if (trimmed.isEmpty) return;
    if (!_initialized) {
      // Use default FA language; change if your app locale is EN by default.
      await init(language: 'fa-IR');
    }
    if (interrupt && _speaking) {
      await _tts.stop();
      _speaking = false;
    }
    await _tts.speak(trimmed);
  }

  /// Stop current speech immediately.
  Future<void> stop() async {
    await _tts.stop();
    _speaking = false;
  }

  /// Optionally call on app shutdown (not strictly required).
  Future<void> dispose() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
