import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_controller.dart';
import 'weather_service.dart';

/// Rutinitas terjadwal buatan user. Contoh: "tiap jam 7 pagi -> briefing".
///
/// Disimpan di SharedPreferences (key: routines_v1) sebagai list:
/// {"id","name","hour","minute","days":[1..7],"actions":[...],"on":true}
///
/// Aksi yang didukung:
/// - {"t":"say","text":"..."}            -> ucapkan teks
/// - {"t":"briefing"}                    -> briefing pagi (cuaca)
/// - {"t":"wifi","on":true/false}        -> Wi-Fi nyala/mati
/// - {"t":"app","keyword":"whatsapp"}    -> buka aplikasi
///
/// CATATAN: scheduler Dart Timer — hanya jalan selama proses app hidup.
/// Untuk keandalan setelah reboot butuh AlarmManager native (roadmap).
class RoutineService {
  void Function(String text)? onRoutine;

  Timer? _timer;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => tick());
    tick();
  }

  void stop() {
    _started = false;
    _timer?.cancel();
    _timer = null;
  }

  static Future<List<Map<String, dynamic>>> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('routines_v1') ?? '[]';
      final list = jsonDecode(raw) as List;
      return list.cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<Map<String, dynamic>> items) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('routines_v1', jsonEncode(items));
  }

  Future<void> tick() async {
    try {
      final now = DateTime.now();
      final items = await load();
      final key = '${now.year}-${now.month}-${now.day} ${now.hour}:${now.minute}';
      for (final r in items) {
        if (!(r['on'] ?? true)) continue;
        if ((r['hour'] ?? -1) != now.hour) continue;
        if ((r['minute'] ?? -1) != now.minute) continue;
        final days = (r['days'] as List?)?.cast<int>() ?? [1, 2, 3, 4, 5, 6, 7];
        if (!days.contains(now.weekday)) continue;
        final id = (r['id'] ?? '').toString();
        final sp = await SharedPreferences.getInstance();
        if ((sp.getString('routine_fired_$id') ?? '') == key) continue;
        await sp.setString('routine_fired_$id', key);
        await run(r);
      }
    } catch (_) {}
  }

  /// Jalankan rutin by map.
  Future<String> run(Map<String, dynamic> r) async {
    final name = (r['name'] ?? 'rutin').toString();
    final actions = (r['actions'] as List?) ?? [];
    final notes = <String>[];
    for (final a in actions) {
      final m = (a as Map).cast<String, dynamic>();
      notes.add(await _exec(m));
    }
    final msg = 'Rutin "$name" jalan, Sir.'
        '${notes.isEmpty ? '' : ' ${notes.join(' ')}'}';
    onRoutine?.call(msg);
    return msg;
  }

  /// Jalankan rutin by nama (dipakai Groq tool run_routine).
  Future<String> runByName(String name) async {
    final items = await load();
    final low = name.toLowerCase();
    for (final r in items) {
      if ((r['name'] ?? '').toString().toLowerCase().contains(low)) {
        if (!(r['on'] ?? true)) return 'Rutin "${r['name']}" lagi mati, Sir.';
        return await run(r);
      }
    }
    return 'Tidak ada rutin bernama "$name", Sir.';
  }

  Future<String> _exec(Map<String, dynamic> a) async {
    try {
      switch ((a['t'] ?? '').toString()) {
        case 'say':
          return (a['text'] ?? '').toString();
        case 'briefing':
          final w = await WeatherService.todaySummary();
          return w.isEmpty
              ? 'Briefing: cuaca tidak terbaca.'
              : 'Briefing: $w.';
        case 'wifi':
          final on = a['on'] == true;
          final r = await AppController.setWifi(on)
              .timeout(const Duration(seconds: 10));
          return r == 'OK'
              ? 'Wi-Fi ${on ? 'nyala' : 'mati'}.'
              : 'Wi-Fi gagal.';
        case 'app':
          final kw = (a['keyword'] ?? '').toString();
          final r = await AppController.openApp(kw)
              .timeout(const Duration(seconds: 10));
          return r == 'OK' ? 'Membuka $kw.' : 'Gagal buka $kw.';
        default:
          return '';
      }
    } catch (_) {
      return '';
    }
  }
}
