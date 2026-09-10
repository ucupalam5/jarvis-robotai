import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Wrapper voice: Speech-to-Text (dengar) + Text-to-Speech (ngomong).
class VoiceService {
  final SpeechToText stt = SpeechToText();
  final FlutterTts tts = FlutterTts();
  bool isListening = false;

  Future<void> initTts() async {
    await tts.setLanguage('id-ID');
    await tts.setSpeechRate(0.95);
    await tts.setPitch(0.9); // suara agak berat ala Jarvis
    await tts.setVolume(1.0);
  }

  Future<bool> initStt() async => await stt.initialize(
        onError: (_) {},
        onStatus: (_) {},
      );

  Future<void> speak(String text) async {
    await tts.stop();
    await tts.speak(text);
  }

  Future<void> stopSpeak() async => await tts.stop();

  /// Dengar sekali (bukan continuous). Callback onResult dipanggil saat final.
  Future<void> listenOnce({
    required void Function(String text, bool finalResult) onResult,
  }) async {
    final ok = await stt.initialize();
    if (!ok) {
      onResult('', true);
      return;
    }
    isListening = true;
    await stt.listen(
      onResult: (r) => onResult(r.recognizedWords, r.finalResult),
      localeId: 'id-ID',
      listenFor: const Duration(seconds: 15),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,
    );
  }

  Future<void> stopListen() async {
    isListening = false;
    await stt.stop();
  }
}
