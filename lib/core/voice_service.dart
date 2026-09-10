import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Wrapper voice: Speech-to-Text (dengar) + Text-to-Speech (ngomong).
/// Dibuat anti-gagal: semua init ada timeout, izin dicek eksplisit,
/// bahasa otomatis fallback kalau paket suara Indonesia belum terinstall.
class VoiceService {
  final SpeechToText stt = SpeechToText();
  final FlutterTts tts = FlutterTts();
  bool isListening = false;
  bool sttReady = false;
  bool ttsReady = false;

  Future<void> initTts() async {
    try {
      // Coba Indonesia dulu, gagal -> pakai bahasa default HP.
      try {
        await tts.setLanguage('id-ID').timeout(const Duration(seconds: 5));
      } catch (_) {
        await tts.setLanguage('en-US').timeout(const Duration(seconds: 5));
      }
      await tts.setSpeechRate(0.95);
      await tts.setPitch(0.9); // suara agak berat ala Jarvis
      await tts.setVolume(1.0);
      ttsReady = true;
    } catch (_) {
      ttsReady = false;
    }
  }

  Future<bool> initStt() async {
    try {
      sttReady = await stt.initialize(onError: (_) {}, onStatus: (_) {})
          .timeout(const Duration(seconds: 10), onTimeout: () => false);
    } catch (_) {
      sttReady = false;
    }
    return sttReady;
  }

  /// true bila izin microphone sudah diberikan.
  Future<bool> get hasMicPermission async {
    try {
      return await stt.hasPermission.timeout(
          const Duration(seconds: 5), onTimeout: () => false);
    } catch (_) {
      return false;
    }
  }

  /// Pilih locale terbaik: Indonesia bila ada, else locale sistem, else default.
  Future<String?> _pickLocale() async {
    try {
      final locales =
          await stt.locales().timeout(const Duration(seconds: 5));
      for (final l in locales) {
        final id = l.localeId.toLowerCase().replaceAll('_', '-');
        if (id.startsWith('id')) return l.localeId;
      }
      try {
        final sys = await stt.systemLocale()
            .timeout(const Duration(seconds: 5));
        if (sys != null) return sys.localeId;
      } catch (_) {}
    } catch (_) {}
    return null; // null = pakai default HP
  }

  Future<void> speak(String text) async {
    if (!ttsReady) return;
    try {
      await tts.stop();
      await tts.speak(text);
    } catch (_) {}
  }

  Future<void> stopSpeak() async {
    try {
      await tts.stop();
    } catch (_) {}
  }

  /// Dengar sekali (bukan continuous). Callback onResult dipanggil saat final.
  /// onLevel menerima 0..1 level suara mic (untuk meter di UI).
  /// Mengembalikan '' + final=true bila: izin mic ditolak / STT tak tersedia /
  /// locale gagal — UI wajib menampilkan pesan penuntun (lihat home_screen).
  Future<void> listenOnce({
    required void Function(String text, bool finalResult) onResult,
    void Function(double level)? onLevel,
  }) async {
    bool ok = false;
    try {
      ok = await stt.initialize(onError: (_) {}, onStatus: (_) {})
          .timeout(const Duration(seconds: 10), onTimeout: () => false);
    } catch (_) {
      ok = false;
    }
    if (!ok) {
      onResult('', true);
      return;
    }
    final locale = await _pickLocale();
    isListening = true;
    try {
      await stt.listen(
        onResult: (r) => onResult(r.recognizedWords, r.finalResult),
        localeId: locale,
        listenFor: const Duration(seconds: 15),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        onSoundLevelChange: onLevel == null
            ? null
            : (level) {
                // level bisa negatif; normalisasi kasar ke 0..1.
                final v = ((level + 2) / 30).clamp(0.0, 1.0);
                onLevel(v);
              },
      );
    } catch (_) {
      isListening = false;
      onResult('', true);
    }
  }

  Future<void> stopListen() async {
    isListening = false;
    try {
      await stt.stop();
    } catch (_) {}
  }
}
