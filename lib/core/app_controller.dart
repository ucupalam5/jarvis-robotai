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
  static Future<String> openLastApp() => _invoke('openLastApp');
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

  // --- Device Admin 1-tap (syarat kunci layar) ---
  static Future<String> adminCheck() => _invoke('adminCheck');
  static Future<String> adminRequest() => _invoke('adminRequest');

  // --- SMS darurat + lokasi (find-my-phone) ---
  static Future<String> requestSms() => _invoke('requestSms');
  static Future<String> requestLoc() => _invoke('requestLoc');

  // --- Kuasa penuh: tulis pengaturan, statistik, baterai, DND, asisten ---
  static Future<String> writeCheck() => _invoke('writeCheck');
  static Future<String> writeRequest() => _invoke('writeRequest');
  static Future<String> setBrightness(int level) =>
      _invoke('setBrightness', {'level': level});
  static Future<String> setScreenTimeout(int ms) =>
      _invoke('setScreenTimeout', {'ms': ms});
  static Future<String> setRotation(bool on) =>
      _invoke('setRotation', {'on': on});
  static Future<String> usageCheck() => _invoke('usageCheck');
  static Future<String> usageRequest() => _invoke('usageRequest');
  static Future<String> usageToday() => _invoke('usageToday');
  static Future<String> batteryCheck() => _invoke('batteryCheck');
  static Future<String> batteryRequest() => _invoke('batteryRequest');
  static Future<String> dndCheck() => _invoke('dndCheck');
  static Future<String> dndRequest() => _invoke('dndRequest');
  static Future<String> assistCheck() => _invoke('assistCheck');
  static Future<String> assistRequest() => _invoke('assistRequest');

  // --- Remote Telegram (service mandiri) ---
  static Future<String> tgRestart() => _invoke('tgRestart');

  // --- Kontak: izin + cari nomor dari nama + chat WA langsung ---
  static Future<String> requestContacts() => _invoke('requestContacts');
  static Future<String> resolveContact(String name) =>
      _invoke('resolveContact', {'name': name});
  static Future<String> openWaChat(String number, String body) =>
      _invoke('openWaChat', {'number': number, 'body': body});

  // --- Notifikasi: baca + balas pesan masuk ---
  static Future<String> notifCheck() => _invoke('notifCheck');
  static Future<String> notifOpenSettings() => _invoke('notifOpenSettings');
  static Future<String> notifLast() => _invoke('notifLast');
  static Future<String> notifReply(String text, String sender) =>
      _invoke('notifReply', {'text': text, 'sender': sender});
  static Future<String> notifAuto(bool on) =>
      _invoke('notifAuto', {'on': on});
  // --- Pengingat terjadwal ---
  static Future<String> setReminder(int id, int at, String text) =>
      _invoke('setReminder', {'id': id, 'at': at, 'text': text});
  static Future<String> cancelReminder(int id) =>
      _invoke('cancelReminder', {'id': id});

  // --- Screenshot layar (AI bisa melihat) ---
  static Future<String> screenshot() => _invoke('screenshot');

  // --- Tangkap layar ke galeri + rekam layar + wifi/bt + foto ---
  static Future<String> saveShot() => _invoke('saveShot');
  static Future<String> startRecording() => _invoke('startRecording');
  static Future<String> stopRecording() => _invoke('stopRecording');
  static Future<String> setWifi(bool on) => _invoke('setWifi', {'on': on});
  static Future<String> setBluetooth(bool on) =>
      _invoke('setBluetooth', {'on': on});
  static Future<String> requestBt() => _invoke('requestBt');
  static Future<String> requestAudio() => _invoke('requestAudio');
  static Future<String> openUrl(String url) =>
      _invoke('openUrl', {'url': url});
  static Future<String> playMusic(String title) =>
      _invoke('playMusic', {'title': title});
  static Future<String> stopMusic() => _invoke('stopMusic');
  static Future<String> accSwipeDown() => _invoke('accSwipeDown');
  static Future<String> takePhoto(bool front) =>
      _invoke('takePhoto', {'front': front});

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
