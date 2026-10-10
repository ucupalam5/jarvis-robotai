import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_controller.dart';
import 'voice_service.dart';
import 'weather_service.dart';

/// JARVIS yang proaktif: ngomong duluan tanpa ditanya.
///
/// - Sapaan + briefing pagi (sekali sehari, jam 06:00–10:00).
/// - Peringatan baterai lemah (< 20%, sekali sampai di-charge lagi).
/// - Nudge pengingat: 15 menit sebelum pengingat jatuh tempo.
///
/// Semua bisa dimatikan di Settings (key: proactive_on).
/// Jam tenang 22:00–06:00: tidak bersuara, hanya teks.
/// Suara bisa dimatikan terpisah (key: proactive_voice) -> teks saja.
class ProactiveService {
  final VoiceService voice;

  /// Dipanggil saat ada pesan proaktif (untuk ditampilkan di chat).
  void Function(String text)? onProactive;

  Timer? _timer;
  bool _started = false;

  ProactiveService(this.voice);

  void start() {
    if (_started) return;
    _started = true;
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => tick());
    tick();
  }

  void stop() {
    _started = false;
    _timer?.cancel();
    _timer = null;
  }

  bool _quietHours(DateTime now) => now.hour >= 22 || now.hour < 6;

  Future<void> tick() async {
    try {
      final sp = await SharedPreferences.getInstance();
      if (!(sp.getBool('proactive_on') ?? true)) return;
      final now = DateTime.now();
      final today = '${now.year}-${now.month}-${now.day}';

      // 1) Sapaan pagi + briefing (sekali sehari, 06:00–10:00).
      final greeted = sp.getString('proactive_greeted') ?? '';
      if (greeted != today && now.hour >= 6 && now.hour < 10) {
        await sp.setString('proactive_greeted', today);
        await _say(
          sp,
          'Selamat pagi, Sir. ${await _briefingLine()}',
          force: false,
        );
        return; // satu pesan proaktif per tick cukup
      }

      // 2) Baterai lemah (< 20%).
      final batWarned = sp.getString('proactive_batwarn') ?? '';
      final bat = await _batteryLevel();
      if (bat >= 0 && bat < 20 && batWarned != today) {
        await sp.setString('proactive_batwarn', today);
        await _say(
          sp,
          'Sir, baterai tinggal $bat persen. Sebaiknya di-charge sekarang.',
          force: false,
        );
        return;
      }
      // Reset penanda kalau sudah di-charge lagi.
      if (bat >= 30 && batWarned.isNotEmpty) {
        await sp.remove('proactive_batwarn');
      }

      // 3) Nudge pengingat 15 menit sebelum jatuh tempo.
      await _nudgeReminders(sp, now);
    } catch (_) {}
  }

  Future<String> _briefingLine() async {
    try {
      final w = await WeatherService.todaySummary();
      if (w.isNotEmpty) return 'Cuaca hari ini: $w.';
    } catch (_) {}
    return 'Semoga harinya lancar.';
  }

  Future<int> _batteryLevel() async {
    try {
      final r = await AppController.batteryCheck()
          .timeout(const Duration(seconds: 10));
      final m = RegExp(r'(\d+)').firstMatch(r);
      if (m != null) return int.parse(m.group(1)!);
    } catch (_) {}
    return -1;
  }

  Future<void> _nudgeReminders(SharedPreferences sp, DateTime now) async {
    try {
      final raw = sp.getString('reminders') ?? '[]';
      // Format: list {"text","epoch"} — toleran kalau kosong/rusak.
      final items = <Map<String, dynamic>>[];
      if (raw.trim().startsWith('[')) {
        // parse manual sederhana tanpa import tambahan
        final matches =
            RegExp(r'"text"\s*:\s*"([^"]+)"[^}]*?"epoch"\s*:\s*(\d+)')
                .allMatches(raw);
        for (final m in matches) {
          items.add({'text': m.group(1), 'epoch': int.parse(m.group(2)!)});
        }
      }
      final nowSec = now.millisecondsSinceEpoch ~/ 1000;
      for (final it in items) {
        final epoch = (it['epoch'] as int?) ?? 0;
        final diff = epoch - nowSec;
        if (diff > 0 && diff <= 15 * 60) {
          final key = 'nudge_$epoch';
          if ((sp.getString(key) ?? '').isEmpty) {
            await sp.setString(key, '1');
            await _say(
              sp,
              'Sir, 15 menit lagi: ${it['text']}.',
              force: false,
            );
            return;
          }
        }
      }
    } catch (_) {}
  }

  Future<void> _say(SharedPreferences sp, String text,
      {required bool force}) async {
    onProactive?.call(text);
    final voiceOn = sp.getBool('proactive_voice') ?? true;
    if (!voiceOn && !force) return;
    if (_quietHours(DateTime.now()) && !force) return;
    try {
      await voice.speak(text).timeout(const Duration(seconds: 30));
    } catch (_) {}
  }
}
