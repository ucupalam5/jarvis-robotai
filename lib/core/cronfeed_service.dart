import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'voice_service.dart';

/// Papan pengumuman: JARVIS HP mengumumkan tugas server yang selesai.
///
/// Server (cron FarestAI) menulis item baru ke `cronfeed.json` di branch
/// `cronfeed`. Service ini poll tiap 15 menit, item baru -> tampil di chat
/// (+ suara kalau `cronfeed_voice` nyala).
///
/// Format cronfeed.json:
/// {"items":[{"id":"...","at":epoch,"title":"...","text":"..."}]}
class CronFeedService {
  final VoiceService voice;

  /// Dipanggil untuk tiap item baru: (title, text).
  void Function(String title, String text)? onFeed;

  Timer? _timer;
  bool _started = false;

  static const _url =
      'https://raw.githubusercontent.com/ucupalam5/jarvis-robotai/cronfeed/cronfeed.json';

  CronFeedService(this.voice);

  void start() {
    if (_started) return;
    _started = true;
    _timer = Timer.periodic(const Duration(minutes: 15), (_) => poll());
    poll();
  }

  void stop() {
    _started = false;
    _timer?.cancel();
    _timer = null;
  }

  Future<void> poll() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (!(sp.getBool('cronfeed_on') ?? true)) return;
      // Cache-buster agar selalu dapat versi terbaru.
      final bust = DateTime.now().millisecondsSinceEpoch;
      final sep = _url.contains('?') ? '&' : '?';
      final res = await http
          .get(Uri.parse('$_url${sep}t=$bust'))
          .timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final items = (data['items'] as List?) ?? [];
      if (items.isEmpty) return;
      final seen = (sp.getStringList('cronfeed_seen') ?? []).toSet();
      final fresh = <Map<String, dynamic>>[];
      for (final it in items) {
        final m = (it as Map).cast<String, dynamic>();
        final id = (m['id'] ?? '').toString();
        if (id.isNotEmpty && !seen.contains(id)) {
          seen.add(id);
          fresh.add(m);
        }
      }
      if (fresh.isEmpty) return;
      await sp.setStringList('cronfeed_seen', seen.toList());
      // Umumkan dari yang terlama ke terbaru.
      for (final m in fresh.reversed) {
        final title = (m['title'] ?? 'Pengumuman').toString();
        final text = (m['text'] ?? '').toString();
        onFeed?.call(title, text);
        if (sp.getBool('cronfeed_voice') ?? true) {
          try {
            await voice.speak('$title. $text').timeout(
                const Duration(seconds: 45));
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
