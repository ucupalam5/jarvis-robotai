import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
/// Otak AI pakai Groq (gratis). Daftar key di https://console.groq.com
/// Model: gpt-oss-120b (utama) + cadangan otomatis bila 404.
class GroqService {
  GroqService(this.apiKey);

  String apiKey;
  static const String _url = 'https://api.groq.com/openai/v1/chat/completions';

  /// Model utama + cadangan. llama pensiun Agu 2026 -> 404.
  /// Urutan: CEPAT dulu (20b, ratusan token/detik) agar respon sat-set,
  /// kalau gagal -> pintar (120b) -> cadangan (qwen).
  static const List<String> models = [
    'openai/gpt-oss-20b',
    'openai/gpt-oss-120b',
    'qwen/qwen3.6-27b',
  ];

  static const String systemPrompt = '''
Kamu adalah JARVIS, asisten RobotAI pribadi ala Iron Man.
ATURAN BAHASA (wajib dipatuhi): SELALU jawab dalam Bahasa Indonesia
(campur Inggris santai ala Jakarta). JANGAN PERNAH jawab full Inggris.
Sopan, panggil user "Sir".
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

  Future<String> chat(String userText, List<Map<String, String>> history,
      {String memory = ''}) async {
    if (apiKey.isEmpty) {
      return 'Sir, Groq API key belum dipasang. Masukkan di Settings ya Sir.';
    }
    final sys = memory.isEmpty
        ? systemPrompt
        : '$systemPrompt\nFakta tentang user (pakai bila relevan):\n$memory';
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': sys},
      ...history.takeLast(10),
      {'role': 'user', 'content': userText},
    ];
    String lastErr = '';
    for (final m in models) {
      try {
        final res = await http
            .post(
              Uri.parse(_url),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $apiKey',
              },
              body: jsonEncode({
                'model': m,
                'messages': messages,
                'temperature': 0.7,
                'max_tokens': 300,
              }),
            )
            .timeout(const Duration(seconds: 15));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          return (data['choices'][0]['message']['content'] as String).trim();
        }
        if (res.statusCode == 401) {
          return 'Sir, API key salah/expired (401). Buat baru di console.groq.com ya Sir.';
        }
        // 404 (model pensiun) / 429 (kuota model ini habis) / 5xx:
        // coba model cadangan (kuota Groq dihitung per model).
        lastErr = '${res.statusCode}';
      } catch (e) {
        lastErr = '$e';
      }
    }
    if (lastErr.contains('429')) {
      return 'Sir, kuota gratis Groq habis (429). Tunggu ~1 menit lalu coba lagi ya Sir.';
    }
    return 'Sir, semua model Groq gagal ($lastErr). Cek internet / key / kuota ya Sir.';
  }

  /// Tanya AI dengan gambar (screenshot layar). Model vision + fallback.
  Future<String> askVision(String imagePath, String question) async {
    if (apiKey.isEmpty) {
      return 'Sir, Groq API key belum dipasang. Masukkan di Settings ya Sir.';
    }
    String b64;
    try {
      final bytes = await File(imagePath).readAsBytes();
      if (bytes.length > 4 * 1024 * 1024) {
        return 'Sir, gambar layar terlalu besar.';
      }
      b64 = base64Encode(bytes);
    } catch (e) {
      return 'Sir, gagal baca gambar layar: $e';
    }
    const models = [
      'meta-llama/llama-4-maverick-17b-128e-instruct',
      'meta-llama/llama-4-scout-17b-16e-instruct',
    ];
    String lastErr = '';
    for (final m in models) {
      try {
        final res = await http
            .post(
              Uri.parse(_url),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $apiKey',
              },
              body: jsonEncode({
                'model': m,
                'temperature': 0.5,
                'max_tokens': 300,
                'messages': [
                  {
                    'role': 'user',
                    'content': [
                      {'type': 'text', 'text': question},
                      {
                        'type': 'image_url',
                        'image_url': {'url': 'data:image/jpeg;base64,$b64'}
                      },
                    ],
                  }
                ],
              }),
            )
            .timeout(const Duration(seconds: 30));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body);
          return (data['choices'][0]['message']['content'] as String).trim();
        }
        if (res.statusCode == 401) {
          return 'Sir, API key salah/expired (401).';
        }
        lastErr = '${res.statusCode}';
      } catch (e) {
        lastErr = '$e';
      }
    }
    return 'Sir, AI vision gagal ($lastErr). Coba lagi ya Sir.';
  }
}

extension _TakeLast<E> on List<E> {
  List<E> takeLast(int n) => length <= n ? toList() : sublist(length - n);
}
