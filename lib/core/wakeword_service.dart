import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'voice_service.dart';

/// Wake word "Hey Jarvis" berbasis STT loop (bukan hardware hotword).
///
/// Cara kerja: dengar terus via speech_to_text, tiap hasil final dicek
/// mengandung varian "jarvis". Kalau ketemu -> panggil [onWake].
///
/// JUJUR: ini BUKAN hotword beneran (kayak "Hey Google"). Mic aktif terus,
/// boros baterai. Default MATI — user yang nyalakan di Settings.
/// Saat TTS bicara, loop dijeda biar tidak dengar suara sendiri.
class WakeWordService {
  final VoiceService voice;

  /// Dipanggil saat wake word terdeteksi.
  void Function()? onWake;

  bool _running = false;
  bool _paused = false;
  bool get isRunning => _running && !_paused;

  static const _variants = [
    'hey jarvis',
    'jarvis',
    'jervis',
    'jarwis',
    'travis',
    'hei jarvis',
  ];

  WakeWordService(this.voice);

  Future<void> start() async {
    final sp = await SharedPreferences.getInstance();
    if (!(sp.getBool('wakeword_on') ?? false)) return;
    if (_running) return;
    _running = true;
    _loop();
  }

  void stop() {
    _running = false;
    unawaited(voice.stopListen());
  }

  /// Jeda sementara (misal saat TTS bicara).
  void pause() => _paused = true;
  void resume() => _paused = false;

  Future<void> _loop() async {
    while (_running) {
      if (_paused) {
        await Future.delayed(const Duration(seconds: 1));
        continue;
      }
      final heard = await _listenChunk();
      if (!_running || _paused) continue;
      final low = heard.toLowerCase();
      if (_variants.any((v) => low.contains(v))) {
        onWake?.call();
        // jeda 3 detik biar tidak double-trigger
        await Future.delayed(const Duration(seconds: 3));
      }
    }
  }

  /// Satu chunk dengar (~10 detik atau sampai final).
  Future<String> _listenChunk() async {
    final c = Completer<String>();
    var done = false;
    void finish(String v) {
      if (!done) {
        done = true;
        if (!c.isCompleted) c.complete(v);
      }
    }

    try {
      await voice.listenOnce(
        onResult: (txt, finalR, _) {
          if (finalR) {
            unawaited(voice.stopListen());
            finish(txt.trim());
          }
        },
      );
      // timeout 12 detik per chunk
      Future.delayed(const Duration(seconds: 12), () {
        unawaited(voice.stopListen());
        finish('');
      });
    } catch (_) {
      finish('');
    }
    return c.future;
  }
}
