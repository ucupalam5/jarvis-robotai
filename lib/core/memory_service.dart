import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Memori jangka panjang Jarvis: fakta tentang user yang menetap
/// antar-sesi ("inget ya ..."), plus app terakhir dibuka.
/// Semua lokal di HP (SharedPreferences), tidak dikirim ke mana pun
/// kecuali sebagai ringkasan konteks ke Groq saat chat.
class MemoryService {
  static const String kFacts = 'jarvis_memory';
  static const String kLastPkg = 'last_app_pkg';
  static const String kLastLabel = 'last_app_label';

  /// [{"k":..., "v":..., "t":millis}]
  static Future<List<Map<String, String>>> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(kFacts) ?? '[]';
      final arr = jsonDecode(raw) as List;
      return arr
          .whereType<Map>()
          .map((e) => {
                'k': (e['k'] ?? '').toString(),
                'v': (e['v'] ?? '').toString(),
              })
          .where((e) => e['k']!.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _save(List<Map<String, String>> list) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
        kFacts,
        jsonEncode(list
            .take(50)
            .map((e) => {
                  'k': e['k'],
                  'v': e['v'],
                  't': DateTime.now().millisecondsSinceEpoch,
                })
            .toList()));
  }

  static Future<void> remember(String key, String value) async {
    final list = await load();
    list.removeWhere(
        (e) => e['k']!.toLowerCase() == key.toLowerCase());
    list.insert(0, {'k': key, 'v': value});
    await _save(list);
  }

  /// Hapus fakta yang mengandung query. Return true bila ada yang dihapus.
  static Future<bool> forget(String query) async {
    final q = query.toLowerCase();
    final list = await load();
    final n = list.length;
    list.removeWhere((e) =>
        e['k']!.toLowerCase().contains(q) ||
        e['v']!.toLowerCase().contains(q));
    if (list.length == n) return false;
    await _save(list);
    return true;
  }

  /// Ringkasan untuk konteks AI (dibatasi agar hemat token).
  static Future<String> summary() async {
    final list = await load();
    if (list.isEmpty) return '';
    final buf = StringBuffer();
    var len = 0;
    for (final e in list.take(10)) {
      final line = '- ${e['k']}: ${e['v']}\n';
      if (len + line.length > 800) break;
      buf.write(line);
      len += line.length;
    }
    return buf.toString();
  }

  static Future<void> noteApp(String pkg, String label) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(kLastPkg, pkg);
      await sp.setString(kLastLabel, label);
    } catch (_) {}
  }

  static Future<MapEntry<String, String>?> lastApp() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final pkg = sp.getString(kLastPkg) ?? '';
      final label = sp.getString(kLastLabel) ?? '';
      if (pkg.isEmpty) return null;
      return MapEntry(label.isEmpty ? pkg : label, pkg);
    } catch (_) {
      return null;
    }
  }
}
