import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Perintah remote: FarestAI (server) bisa menyuruh HP melakukan sesuatu.
///
/// Server menulis ke `remote-cmd.json` di branch `cronfeed`:
/// {"commands":[{"id":"c123","at":epoch,"action":"say|open_app|run_routine",
///               "args":{"text":"...","keyword":"...","name":"..."}}]}
///
/// Service ini poll tiap 5 menit, mengeksekusi perintah yang belum
/// dijalankan (dilacak di prefs `remotecmd_done`), dan melewatkan
/// perintah yang umurnya > 1 jam.
class RemoteCmdService {
  /// Eksekutor: (action, args) -> pesan hasil untuk chat.
  Future<String> Function(String action, Map<String, dynamic> args)? onCommand;

  Timer? _timer;
  bool _started = false;

  static const _url =
      'https://raw.githubusercontent.com/ucupalam5/jarvis-robotai/cronfeed/remote-cmd.json';

  void start() {
    if (_started) return;
    _started = true;
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => poll());
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
      final bust = DateTime.now().millisecondsSinceEpoch;
      final res = await http
          .get(Uri.parse('$_url?t=$bust'))
          .timeout(const Duration(seconds: 25));
      if (res.statusCode != 200) return;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final cmds = (data['commands'] as List?) ?? [];
      if (cmds.isEmpty) return;
      final done = (sp.getStringList('remotecmd_done') ?? []).toSet();
      final nowSec = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      var changed = false;
      for (final c in cmds) {
        final m = (c as Map).cast<String, dynamic>();
        final id = (m['id'] ?? '').toString();
        if (id.isEmpty || done.contains(id)) continue;
        final at = (m['at'] as num?)?.toInt() ?? 0;
        if (nowSec - at > 3600) {
          done.add(id); // kedaluwarsa: tandai selesai tanpa eksekusi
          changed = true;
          continue;
        }
        done.add(id);
        changed = true;
        final action = (m['action'] ?? '').toString();
        final args = (m['args'] as Map?)?.cast<String, dynamic>() ?? {};
        try {
          final msg = await onCommand?.call(action, args);
          if (msg != null && msg.isNotEmpty) {
            // onCommand sudah menampilkan ke chat sendiri bila perlu.
          }
        } catch (_) {}
      }
      if (changed) {
        // Batasi 100 id terakhir biar prefs tidak membengkak.
        final list = done.toList();
        await sp.setStringList(
            'remotecmd_done', list.sublist(list.length > 100 ? list.length - 100 : 0));
      }
    } catch (_) {}
  }
}
