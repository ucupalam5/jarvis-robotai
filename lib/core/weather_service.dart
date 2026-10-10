import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Cuaca via Open-Meteo (GRATIS, tanpa API key).
/// https://open-meteo.com
///
/// Koordinat default: Jakarta. Bisa diubah di Settings Jarvis
/// (key SharedPreferences: weather_lat, weather_lon).
class WeatherService {
  static const _url = 'https://api.open-meteo.com/v1/forecast';

  /// Kode cuaca WMO -> Bahasa Indonesia singkat.
  static String _desc(int code) {
    if (code == 0) return 'cerah';
    if (code <= 3) return 'berawan';
    if (code <= 48) return 'berkabut';
    if (code <= 57) return 'gerimis';
    if (code <= 67) return 'hujan';
    if (code <= 77) return 'hujan salju ringan';
    if (code <= 82) return 'hujan deras';
    if (code <= 86) return 'hujan salju';
    if (code == 95) return 'badai petir';
    return 'badai petir disertai hujan es';
  }

  /// Ringkasan cuaca hari ini, siap diucapkan TTS.
  /// Return string kosong bila gagal (briefing tetap jalan tanpa cuaca).
  static Future<String> todaySummary() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final lat = sp.getDouble('weather_lat') ?? -6.2;
      final lon = sp.getDouble('weather_lon') ?? 106.85;
      final uri = Uri.parse(
        '$_url?latitude=$lat&longitude=$lon'
        '&current=temperature_2m,weather_code'
        '&daily=temperature_2m_max,temperature_2m_min,precipitation_probability_max'
        '&timezone=Asia%2FJakarta&forecast_days=1',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return '';
      final d = jsonDecode(res.body) as Map<String, dynamic>;
      final cur = (d['current'] ?? {}) as Map<String, dynamic>;
      final daily = (d['daily'] ?? {}) as Map<String, dynamic>;
      final t = (cur['temperature_2m'] as num?)?.round();
      final code = (cur['weather_code'] as num?)?.toInt() ?? 0;
      final maxT = ((daily['temperature_2m_max'] as List?)?.isNotEmpty ?? false)
          ? ((daily['temperature_2m_max'] as List).first as num).round()
          : null;
      final minT = ((daily['temperature_2m_min'] as List?)?.isNotEmpty ?? false)
          ? ((daily['temperature_2m_min'] as List).first as num).round()
          : null;
      final rainP =
          ((daily['precipitation_probability_max'] as List?)?.isNotEmpty ?? false)
              ? ((daily['precipitation_probability_max'] as List).first as num)
                  .round()
              : null;
      final parts = <String>['Cuaca hari ini ${_desc(code)}'];
      if (t != null) parts.add('suhu $t derajat');
      if (maxT != null && minT != null) {
        parts.add('maksimal $maxT, minimal $minT derajat');
      }
      var s = '${parts.join(', ')}. ';
      if (rainP != null && rainP >= 50) {
        s += 'Peluang hujan $rainP persen, bawa payung ya Sir. ';
      }
      return s;
    } catch (_) {
      return '';
    }
  }
}
