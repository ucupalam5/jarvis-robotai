import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_controller.dart';

/// Pengingat berbasis lokasi (geofence sederhana).
///
/// "Ingat lokasi kantor" -> tandai posisi HP sekarang (radius 200 m).
/// Tiap 5 menit cek lokasi terakhir; kalau masuk radius dan belum
/// di-trigger hari ini -> sapa via [onGeofence].
///
/// Butuh: izin lokasi + GPS nyala. Pakai channel native `getLocation`
/// (perlu ditambahkan di MainActivity + AppController).
class GeofenceService {
  void Function(String text)? onGeofence;

  Timer? _timer;
  bool _started = false;

  void start() {
    if (_started) return;
    _started = true;
    _timer = Timer.periodic(const Duration(minutes: 5), (_) => check());
    check();
  }

  void stop() {
    _started = false;
    _timer?.cancel();
    _timer = null;
  }

  static Future<List<Map<String, dynamic>>> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString('geofences_v1') ?? '[]';
      return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  static Future<void> save(List<Map<String, dynamic>> items) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString('geofences_v1', jsonEncode(items));
  }

  /// Tambah geofence di lokasi SAAT INI. Return pesan untuk user.
  static Future<String> addHere(String label, String text,
      {double radius = 200}) async {
    final loc = await AppController.getLocation()
        .timeout(const Duration(seconds: 25));
    final m = RegExp(r'LOKASI:(-?[\d.]+),(-?[\d.]+)').firstMatch(loc);
    if (m == null) {
      return 'Gagal baca lokasi, Sir. Nyalakan GPS + izinkan lokasi dulu ya.';
    }
    final items = await load();
    items.add({
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'label': label,
      'lat': double.parse(m.group(1)!),
      'lon': double.parse(m.group(2)!),
      'radius': radius,
      'text': text,
      'triggered': '',
    });
    await save(items);
    return 'Siap Sir. Nanti pas sampai di $label, saya ingatkan: "$text".';
  }

  Future<void> check() async {
    try {
      final items = await load();
      if (items.isEmpty) return;
      final loc =
          await AppController.getLocation().timeout(const Duration(seconds: 25));
      final m = RegExp(r'LOKASI:(-?[\d.]+),(-?[\d.]+)').firstMatch(loc);
      if (m == null) return;
      final lat = double.parse(m.group(1)!);
      final lon = double.parse(m.group(2)!);
      final today = DateTime.now().toIso8601String().substring(0, 10);
      var changed = false;
      for (final g in items) {
        if ((g['triggered'] ?? '') == today) continue;
        final d = _meters(lat, lon, (g['lat'] as num).toDouble(),
            (g['lon'] as num).toDouble());
        if (d <= ((g['radius'] as num?)?.toDouble() ?? 200)) {
          g['triggered'] = today;
          changed = true;
          onGeofence?.call(
              'Anda sampai di ${g['label']}, Sir. ${g['text']}');
        }
      }
      if (changed) await save(items);
    } catch (_) {}
  }

  double _meters(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return 2 * r * asin(sqrt(a));
  }
}
