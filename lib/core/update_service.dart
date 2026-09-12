import 'dart:convert';

import 'package:http/http.dart' as http;

/// Auto-update dari GitHub Release (tanpa hapus-install manual).
/// PENTING: samakan kAppVersion dengan pubspec + tag release terbaru
/// setiap kali rilis, kalau tidak app akan tawarkan update ke diri sendiri.
class UpdateService {
  static const String kAppVersion = '1.9.0';
  static const String kRepo = 'ucupalam5/jarvis-robotai';
  static const String _latestUrl =
      'https://api.github.com/repos/$kRepo/releases/latest';

  /// Return (adaUpdate, tag, urlApk, catatan).
  static Future<(bool, String, String, String)> check() async {
    try {
      final res = await http.get(Uri.parse(_latestUrl)).timeout(
            const Duration(seconds: 15),
          );
      if (res.statusCode == 404) {
        return (false, '', '', 'Belum ada rilis.');
      }
      if (res.statusCode != 200) {
        return (false, '', '', 'Gagal cek update (${res.statusCode}).');
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final tag = (data['tag_name'] ?? '').toString();
      if (tag.isEmpty || !_isNewer(tag, kAppVersion)) {
        return (false, tag, '', 'Sudah versi terbaru.');
      }
      String url = '';
      final assets = (data['assets'] ?? []) as List;
      for (final a in assets) {
        final name = (a['name'] ?? '').toString();
        if (name.endsWith('.apk')) {
          url = (a['browser_download_url'] ?? '').toString();
          break;
        }
      }
      if (url.isEmpty) return (false, tag, '', 'Rilis $tag tanpa APK.');
      final notes = (data['body'] ?? '').toString();
      return (true, tag, url, notes);
    } catch (e) {
      return (false, '', '', 'Tidak bisa cek update: $e');
    }
  }

  /// true bila tag (misal v1.2.0) lebih baru dari current (misal 1.1.0).
  static bool _isNewer(String tag, String current) {
    List<int> parts(String v) {
      return v
          .replaceAll(RegExp(r'^[^0-9]*'), '')
          .split('.')
          .map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
          .toList();
    }

    final a = parts(tag);
    final b = parts(current);
    for (var i = 0; i < 3; i++) {
      final x = i < a.length ? a[i] : 0;
      final y = i < b.length ? b[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }
}
