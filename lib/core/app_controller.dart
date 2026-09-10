import 'package:flutter/services.dart';

/// Jembatan ke native Android (MainActivity.kt) untuk kontrol HP.
/// Channel name harus sama persis: "jarvis/control"
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
  static Future<String> screenOff() => _invoke('lockScreen'); // sama: kunci+mati layar
  static Future<String> toggleFlashlight(bool on) =>
      _invoke('flashlight', {'on': on});
  static Future<String> setVolumeUp() => _invoke('volumeUp');
  static Future<String> setVolumeDown() => _invoke('volumeDown');

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
}
