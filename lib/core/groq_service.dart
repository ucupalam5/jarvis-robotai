import 'dart:convert';
import 'package:http/http.dart' as http;

/// Otak AI pakai Groq (gratis). Daftar key di https://console.groq.com
/// Model default: llama-3.3-70b-versatile (cepat + pintar, gratis).
class GroqService {
  GroqService(this.apiKey);

  String apiKey;
  static const String _url = 'https://api.groq.com/openai/v1/chat/completions';
  static const String model = 'llama-3.3-70b-versatile';

  static const String systemPrompt = '''
Kamu adalah JARVIS, asisten RobotAI pribadi ala Iron Man.
Gaya bicara: Indonesia campur Inggris, santai, singkat, sopan, panggil user "Sir".
Tugas: bantu kontrol HP Android, jawab pertanyaan apapun, kasih saran.
Kalau user minta buka/tutup aplikasi, jawab konfirmasi singkat seperti "Siap Sir, membuka WhatsApp."
Jawaban maksimal 3 kalimat kecuali diminta menjelaskan panjang.
''';

  /// Cek key ke server Groq. Return (valid, pesan).
  Future<(bool, String)> validateKey(String key) async {
    if (key.isEmpty) return (false, 'Key kosong.');
    try {
      final res = await http.get(
        Uri.parse('https://api.groq.com/openai/v1/models'),
        headers: {'Authorization': 'Bearer $key'},
      ).timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        return (true, 'API key VALID ✓ Sir. Groq tersambung.');
      }
      if (res.statusCode == 401) {
        return (
          false,
          'API key SALAH/expired (401). Buat baru di console.groq.com > API Keys.'
        );
      }
      return (false, 'Groq jawab ${res.statusCode}. Cek koneksi/kuota ya Sir.');
    } catch (e) {
      return (false, 'Tidak bisa hubungi Groq: $e');
    }
  }

  Future<String> chat(String userText, List<Map<String, String>> history) async {
    if (apiKey.isEmpty) {
      return 'Sir, Groq API key belum dipasang. Masukkan di Settings ya Sir.';
    }
    try {
      final messages = <Map<String, String>>[
        {'role': 'system', 'content': systemPrompt},
        ...history.takeLast(10),
        {'role': 'user', 'content': userText},
      ];
      final res = await http
          .post(
            Uri.parse(_url),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode({
              'model': model,
              'messages': messages,
              'temperature': 0.7,
              'max_tokens': 500,
            }),
          )
          .timeout(const Duration(seconds: 30));

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (data['choices'][0]['message']['content'] as String).trim();
      } else {
        return 'Sir, koneksi ke Groq gagal (${res.statusCode}). Cek API key / kuota gratisnya ya Sir.';
      }
    } catch (e) {
      return 'Sir, saya offline nih. Cek internet ya Sir. Error: $e';
    }
  }
}

extension _TakeLast<E> on List<E> {
  List<E> takeLast(int n) => length <= n ? toList() : sublist(length - n);
}
