import 'package:flutter/services.dart';

/// Jembatan ke native Android (MainActivity.kt) untuk kontrol HP.
/// Channel name harus sama persis: "jarvis/control"
/// VERSI MINIMAL: hanya API standar, tanpa Shizuku / overlay.
class AppController {
  static const MethodChannel _ch = MethodChannel('jarvis/control');

  static Future<String> _invoke(String method, [dynamic args]) async {
    try {
      final r = await _ch.invokeMethod<String>(method, args);
      return r ?? 'OK';
    } on PlatformException catch (e) {
      return 'Gagal: ${e.message}';
    } catch (e) {
      return 'Gagal: $e';
    }
  }

  static Future<String> openApp(String keyword) =>
      _invoke('openApp', {'keyword': keyword});
  static Future<String> closeApp() => _invoke('closeApp');
  static Future<String> goHome() => _invoke('goHome');
  static Future<String> lockScreen() => _invoke('lockScreen');
  static Future<String> wakeUp() => _invoke('wakeUp');
  static Future<String> getBattery() => _invoke('getBattery');
  static Future<String> setAlarm(int hour, int minute, String label) =>
      _invoke('setAlarm', {'hour': hour, 'minute': minute, 'label': label});
  static Future<String> dial(String number) =>
      _invoke('dial', {'number': number});
  static Future<String> sms(String number, String body) =>
      _invoke('sms', {'number': number, 'body': body});
  static Future<String> webSearch(String query) =>
      _invoke('webSearch', {'query': query});
  static Future<String> openSettingsPage(String page) =>
      _invoke('openSettingsPage', {'page': page});
  static Future<String> requestMic() => _invoke('requestMic');
  static Future<String> pickImage() => _invoke('pickImage');

  // --- Shizuku (ADB tanpa root, via ShizukuHelper.kt) ---
  static Future<String> shizukuCheck() => _invoke('shizukuCheck');
  static Future<String> shizukuRequest() => _invoke('shizukuRequest');
  static Future<String> shizukuExec(String cmd) =>
      _invoke('shizukuExec', {'cmd': cmd});
  static Future<String> shizukuWakeUnlock(String pin) =>
      _invoke('shizukuWakeUnlock', {'pin': pin});
  static Future<String> shizukuTap(int x, int y) =>
      _invoke('shizukuTap', {'x': x, 'y': y});
  static Future<String> shizukuType(String text) =>
      _invoke('shizukuType', {'text': text});
  static Future<String> toggleFlashlight(bool on) =>
      _invoke('flashlight', {'on': on});
  static Future<String> setVolumeUp() => _invoke('volumeUp');
  static Future<String> setVolumeDown() => _invoke('volumeDown');
}
