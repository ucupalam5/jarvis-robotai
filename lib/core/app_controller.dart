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

  // --- Popup robot native ---
  static Future<String> overlayShow() => _invoke('overlayShow');
  static Future<String> overlayHide() => _invoke('overlayHide');
  static Future<String> overlayActive() => _invoke('overlayActive');
  static Future<String> overlayPerm() => _invoke('overlayPerm');
  static Future<String> overlayRequest() => _invoke('overlayRequest');

  // --- Handsfree wake lock ---
  static Future<String> handsfreeWake(bool on) =>
      _invoke('handsfreeWake', {'on': on});

  // --- Popup tap -> auto dengar + izin notifikasi/kamera ---
  static Future<String> consumeAutolisten() => _invoke('consumeAutolisten');
  static Future<String> requestNotif() => _invoke('requestNotif');
  static Future<String> requestCamera() => _invoke('requestCamera');

  // --- Kontrol penuh HP ---
  static Future<String> listApps() => _invoke('listApps');
  static Future<String> ringerMode(String mode) =>
      _invoke('ringerMode', {'mode': mode});
  static Future<String> mediaKey(int code) =>
      _invoke('mediaKey', {'code': code});

  // --- Ikon aplikasi (activity-alias, tanpa install ulang) ---
  static Future<String> setIcon(String variant) =>
      _invoke('setIcon', {'variant': variant});

  // --- Shortcut galeri ke home screen ---
  static Future<String> pinShortcut(String path, String label) =>
      _invoke('pinShortcut', {'path': path, 'label': label});

  // --- Auto-update GitHub Release ---
  static Future<String> downloadUpdate(String url) =>
      _invoke('downloadUpdate', {'url': url});

  // --- Kontak: izin + cari nomor dari nama + chat WA langsung ---
  static Future<String> requestContacts() => _invoke('requestContacts');
  static Future<String> resolveContact(String name) =>
      _invoke('resolveContact', {'name': name});
  static Future<String> openWaChat(String number, String body) =>
      _invoke('openWaChat', {'number': number, 'body': body});

  // --- Pengingat terjadwal ---
  static Future<String> setReminder(int id, int at, String text) =>
      _invoke('setReminder', {'id': id, 'at': at, 'text': text});
  static Future<String> cancelReminder(int id) =>
      _invoke('cancelReminder', {'id': id});

  // --- Screenshot layar (AI bisa melihat) ---
  static Future<String> screenshot() => _invoke('screenshot');

  // --- Otomatisasi via Accessibility (tanpa root/aplikasi tambahan) ---
  static Future<String> accCheck() => _invoke('accCheck');
  static Future<String> accOpenSettings() => _invoke('accOpenSettings');
  static Future<String> accTap(int x, int y) =>
      _invoke('accTap', {'x': x, 'y': y});
  static Future<String> accSwipeUp() => _invoke('accSwipeUp');
  static Future<String> accType(String text) =>
      _invoke('accType', {'text': text});
  static Future<String> accClickSend() => _invoke('accClickSend');
  static Future<String> toggleFlashlight(bool on) =>
      _invoke('flashlight', {'on': on});
  static Future<String> setVolumeUp() => _invoke('volumeUp');
  static Future<String> setVolumeDown() => _invoke('volumeDown');
}
