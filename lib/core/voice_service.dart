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
  /// true bila ada voice Indonesia terinstall (kalau tidak, Jarvis
  /// terpaksa bersuara Inggris -> user wajib install paket suara).
  bool ttsIndonesian = false;

  Future<void> initTts() async {
    try {
      // Kunci engine Google (paling lengkap paket Indonesianya).
      try {
        await tts.setEngine('com.google.android.tts')
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
      // Paksa suara Indonesia: cari voice 'id' yang terinstall lalu kunci.
      try {
        await tts.setLanguage('id-ID').timeout(const Duration(seconds: 5));
        final voices = await tts.getVoices.timeout(const Duration(seconds: 5));
        if (voices is List) {
          for (final v in voices) {
            if (v is Map) {
              final loc = (v['locale'] ?? '').toString().toLowerCase();
              if (loc.startsWith('id')) {
                await tts.setVoice(
                    {'name': v['name'], 'locale': v['locale']});
                ttsIndonesian = true;
                break;
              }
            }
          }
        }
      } catch (_) {}
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

  /// SELALU Indonesia: pakai locale id bila ada, else paksa 'id-ID'
  /// (recognizer online Google tetap paham). Jangan pernah fallback Inggris.
  Future<String> _pickLocale() async {
    try {
      final locales =
          await stt.locales().timeout(const Duration(seconds: 5));
      for (final l in locales) {
        final id = l.localeId.toLowerCase().replaceAll('_', '-');
        if (id.startsWith('id')) return l.localeId;
      }
    } catch (_) {}
    return 'id-ID';
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

  /// Dengar sekali (bukan continuous).
  /// onResult(text, final, alternates): alternates = tebakan lain STT,
  /// dipakai home untuk akurasi (coba tiap tebakan ke perintah lokal).
  /// onLevel menerima 0..1 level suara mic (untuk meter di UI).
  Future<void> listenOnce({
    required void Function(String text, bool finalResult, List<String> alternates)
        onResult,
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
      onResult('', true, const []);
      return;
    }
    final locale = await _pickLocale();
    isListening = true;
    try {
      await stt.listen(
        onResult: (r) {
          final alts = <String>[];
          try {
            for (final a in r.alternates) {
              final w = a.recognizedWords.trim();
              if (w.isNotEmpty && w != r.recognizedWords.trim()) {
                alts.add(w);
              }
            }
          } catch (_) {}
          onResult(r.recognizedWords, r.finalResult, alts);
        },
        localeId: locale,
        // Respon cepat: jeda hening 2 detik langsung dianggap selesai bicara.
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 2),
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
      onResult('', true, const []);
    }
  }

  Future<void> stopListen() async {
    isListening = false;
    try {
      await stt.stop();
    } catch (_) {}
  }
}
