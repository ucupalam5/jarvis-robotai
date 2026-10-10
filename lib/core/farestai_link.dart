import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Jembatan JARVIS HP <-> FarestAI (server).
///
/// Dua arah via file JSON di branch `cronfeed` repo jarvis-robotai:
///
/// HP -> Server (butuh GitHub PAT di Settings, scope repo contents:write):
/// - "tanya farestai ...": pertanyaan berat -> antre di farestai-inbox.json,
///   dijawab FarestAI dalam ~10-15 menit, jawaban masuk papan pengumuman.
/// - "ingat ini: ...": fakta untuk memori FarestAI.
///
/// Server -> HP (tanpa auth, baca publik):
/// - shared-memory.json: fakta pilihan tentang user, ditarik tiap 6 jam
///   dan disuntik ke system prompt Groq biar JARVIS kenal user.
///
/// CATATAN KEAMANAN: PAT disimpan di SharedPreferences (privat per app).
/// Pakai fine-grained token yang HANYA boleh tulis ke repo ini saja.
class FarestAiLink {
  static const _owner = 'ucupalam5';
  static const _repo = 'jarvis-robotai';
  static const _branch = 'cronfeed';
  static const _api = 'https://api.github.com';

  static Future<String?> _pat() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final t = (sp.getString('github_pat') ?? '').trim();
      return t.isEmpty ? null : t;
    } catch (_) {
      return null;
    }
  }

  static Map<String, String> _headers(String pat) => {
        'Authorization': 'Bearer $pat',
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  /// Baca file JSON dari branch cronfeed (butuh PAT untuk baca/tulis).
  static Future<Map<String, dynamic>?> _readJson(
      String path, String pat) async {
    try {
      final res = await http
          .get(
            Uri.parse(
                '$_api/repos/$_owner/$_repo/contents/$path?ref=$_branch'),
            headers: _headers(pat),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final content = (data['content'] ?? '').toString().replaceAll('\n', '');
      if (content.isEmpty) return {'_sha': data['sha']};
      return {
        ...jsonDecode(utf8.decode(base64.decode(content)))
            as Map<String, dynamic>,
        '_sha': data['sha'],
      };
    } catch (_) {
      return null;
    }
  }

  static Future<bool> _writeJson(
      String path, Map<String, dynamic> json, String sha, String pat,
      {required String message}) async {
    try {
      final clean = Map<String, dynamic>.from(json)..remove('_sha');
      final res = await http
          .put(
            Uri.parse('$_api/repos/$_owner/$_repo/contents/$path'),
            headers: _headers(pat),
            body: jsonEncode({
              'message': message,
              'content': base64.encode(utf8.encode(jsonEncode(clean))),
              'sha': sha,
              'branch': _branch,
            }),
          )
          .timeout(const Duration(seconds: 25));
      return res.statusCode == 200 || res.statusCode == 201;
    } catch (_) {
      return false;
    }
  }

  /// Kirim pertanyaan ke FarestAI. Return pesan untuk user.
  static Future<String> askQuestion(String text) async {
    final pat = await _pat();
    if (pat == null) {
      return 'Belum ada GitHub token, Sir. Isi di Settings > FarestAI Link dulu ya (cukup sekali).';
    }
    final inbox = await _readJson('farestai-inbox.json', pat);
    if (inbox == null) {
      return 'Gagal buka kotak pesan FarestAI, Sir. Cek internet / token ya.';
    }
    final questions = (inbox['questions'] as List?) ?? [];
    // Batasi 5 antrean biar tidak spam.
    final open =
        questions.where((q) => (q as Map)['status'] == 'open').length;
    if (open >= 5) {
      return 'Antrean ke FarestAI penuh (5), Sir. Tunggu jawaban dulu ya.';
    }
    questions.add({
      'id': 'q${DateTime.now().millisecondsSinceEpoch}',
      'at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'from': 'jarvis-app',
      'text': text,
      'status': 'open',
    });
    inbox['questions'] = questions;
    final ok = await _writeJson('farestai-inbox.json', inbox,
        (inbox['_sha'] ?? '').toString(), pat,
        message: 'jarvis: pertanyaan baru untuk FarestAI');
    if (!ok) {
      return 'Gagal kirim ke FarestAI, Sir. Coba lagi ya.';
    }
    return 'Siap, Sir. Pertanyaan diteruskan ke FarestAI. Jawabannya butuh beberapa menit — saya kabari begitu datang.';
  }

  /// Titip fakta ke memori FarestAI.
  static Future<String> rememberFact(String fact) async {
    final pat = await _pat();
    if (pat == null) {
      return 'Belum ada GitHub token, Sir. Isi di Settings > FarestAI Link dulu ya.';
    }
    final inbox = await _readJson('farestai-inbox.json', pat);
    if (inbox == null) return 'Gagal buka kotak pesan, Sir.';
    final facts = (inbox['facts'] as List?) ?? [];
    facts.add({
      'at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'text': fact,
    });
    inbox['facts'] = facts;
    final ok = await _writeJson('farestai-inbox.json', inbox,
        (inbox['_sha'] ?? '').toString(), pat,
        message: 'jarvis: fakta baru untuk memori FarestAI');
    return ok
        ? 'Dicatat, Sir. FarestAI akan mengingat: "$fact".'
        : 'Gagal mencatat, Sir. Coba lagi ya.';
  }

  /// Tarik memori bersama dari server (publik, tanpa PAT).
  /// Return teks fakta, atau '' bila gagal.
  static Future<String> pullSharedMemory() async {
    try {
      final bust = DateTime.now().millisecondsSinceEpoch;
      final res = await http
          .get(Uri.parse(
              'https://raw.githubusercontent.com/$_owner/$_repo/$_branch/shared-memory.json?t=$bust'))
          .timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) return '';
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      return (data['facts_for_jarvis'] ?? '').toString().trim();
    } catch (_) {
      return '';
    }
  }
}
