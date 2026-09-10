import 'app_controller.dart';

/// Hasil parsing perintah suara -> aksi lokal atau lempar ke AI.
class ParsedCommand {
  final bool handledLocally;
  final String reply; // kalimat yang diucapkan Jarvis
  final Future<String> Function()? action;
  ParsedCommand({required this.handledLocally, required this.reply, this.action});
}

/// Mapping kata Indonesia -> package aplikasi populer.
/// Bisa ditambah sendiri. Kalau tidak ketemu, Android akan coba tebak via Play Store intent.
const Map<String, String> appMap = {
  'whatsapp': 'com.whatsapp',
  'wa': 'com.whatsapp',
  'youtube': 'com.google.android.youtube',
  'yt': 'com.google.android.youtube',
  'chrome': 'com.android.chrome',
  'browser': 'com.android.chrome',
  'kamera': 'com.android.camera',
  'camera': 'com.android.camera',
  'galeri': 'com.google.android.apps.photos',
  'foto': 'com.google.android.apps.photos',
  'maps': 'com.google.android.apps.maps',
  'map': 'com.google.android.apps.maps',
  'gmail': 'com.google.android.gm',
  'email': 'com.google.android.gm',
  'telepon': 'com.android.dialer',
  'kontak': 'com.android.contacts',
  'pesan': 'com.google.android.apps.messaging',
  'sms': 'com.google.android.apps.messaging',
  'kalkulator': 'com.google.android.calculator',
  'jam': 'com.google.android.deskclock',
  'alarm': 'com.google.android.deskclock',
  'kalender': 'com.google.android.calendar',
  'drive': 'com.google.android.apps.docs',
  'spotify': 'com.spotify.music',
  'instagram': 'com.instagram.android',
  'ig': 'com.instagram.android',
  'tiktok': 'com.zhiliaoapp.musically',
  'facebook': 'com.facebook.katana',
  'fb': 'com.facebook.katana',
  'telegram': 'org.telegram.messenger',
  'shopee': 'com.shopee.id',
  'tokopedia': 'com.tokopedia.tkpd',
  'dana': 'id.dana',
  'ovo': 'ovo.id',
  'gopay': 'com.gojek.gopay',
  'gojek': 'com.gojek.app',
  'grab': 'com.grabtaxi.passenger',
  'mobile legend': 'com.mobile.legends',
  'ml': 'com.mobile.legends',
  'free fire': 'com.dts.freefireth',
  'ff': 'com.dts.freefireth',
  'pubg': 'com.tencent.ig',
  'settings': 'com.android.settings',
  'pengaturan': 'com.android.settings',
  'setelan': 'com.android.settings',
  'play store': 'com.android.vending',
  'playstore': 'com.android.vending',
};

ParsedCommand parseLocalCommand(String rawText) {
  final t = rawText.toLowerCase().trim();

  // --- BUKA APLIKASI: "buka whatsapp", "open youtube", "tolong bukain ig" ---
  if (t.contains('buka') || t.startsWith('open') || t.contains('jalankan')) {
    String target = t
        .replaceAll(RegExp(r'(tolong|dong|coba|buka|bukain|bukakan|open|jalankan)'), '')
        .trim();
    // normalisasi "wasap" typo umum STT
    if (target.contains('wasap')) target = 'whatsapp';
    if (target.isEmpty) {
      return ParsedCommand(
          handledLocally: true, reply: 'Sir, mau buka aplikasi apa?');
    }
    String keyword = appMap[target] ?? target;
    // cari partial match: "ig" di dalam map
    appMap.forEach((k, v) {
      if (target == k || target.contains(k)) keyword = v;
    });
    final kw = keyword;
    final label = target;
    return ParsedCommand(
      handledLocally: true,
      reply: 'Siap Sir, membuka $label.',
      action: () => AppController.openApp(kw),
    );
  }

  // --- TUTUP APLIKASI ---
  if (t.contains('tutup') || t.contains('close') || t.contains('tutup aplikasi')) {
    return ParsedCommand(
      handledLocally: true,
      reply: 'Siap Sir, menutup aplikasi.',
      action: () => AppController.closeApp(),
    );
  }

  // --- KEMBALI KE HOME ---
  if (t.contains('kembali') && t.contains('home') ||
      t == 'home' ||
      t.contains('ke beranda')) {
    return ParsedCommand(
      handledLocally: true,
      reply: 'Kembali ke home, Sir.',
      action: () => AppController.goHome(),
    );
  }

  // --- NYALAKAN LAYAR (layar-mati, bukan mati total).
  // Tanpa Shizuku: hanya menyalakan layar via WakeLock.
  // Kalau ada PIN/fingerprint, buka manual ya Sir (blokir keamanan Android).
  if (t.contains('nyalakan layar') ||
      t.contains('nyalakan hp') ||
      t.contains('hidupkan layar') ||
      t.contains('bangun') ||
      t.contains('wake up')) {
    return ParsedCommand(
      handledLocally: true,
      reply: 'Menyalakan layar, Sir.',
      action: () => AppController.wakeUp(),
    );
  }

  // --- KUNCI / MATIKAN LAYAR ---
  if ((t.contains('kunci') && t.contains('layar')) ||
      t.contains('matikan layar') ||
      t.contains('matikan hp') ||
      t.contains('kunci hp') ||
      t.contains('lock')) {
    return ParsedCommand(
      handledLocally: true,
      reply: 'Mengunci layar sekarang, Sir.',
      action: () => AppController.lockScreen(),
    );
  }

  // --- SENTER ---
  if (t.contains('senter') || t.contains('flashlight') || t.contains('lampu')) {
    final on = !(t.contains('mati'));
    return ParsedCommand(
      handledLocally: true,
      reply: on ? 'Senter dinyalakan, Sir.' : 'Senter dimatikan, Sir.',
      action: () => AppController.toggleFlashlight(on),
    );
  }

  // --- VOLUME ---
  if (t.contains('volume') || t.contains('suara')) {
    if (t.contains('naik') || t.contains('besar') || t.contains('keras') || t.contains('up')) {
      return ParsedCommand(
        handledLocally: true,
        reply: 'Volume dinaikkan, Sir.',
        action: () => AppController.setVolumeUp(),
      );
    }
    if (t.contains('turun') || t.contains('kecil') || t.contains('pelan') || t.contains('down')) {
      return ParsedCommand(
        handledLocally: true,
        reply: 'Volume diturunkan, Sir.',
        action: () => AppController.setVolumeDown(),
      );
    }
  }

  // --- Bukan perintah lokal -> lempar ke Groq AI ---
  return ParsedCommand(handledLocally: false, reply: '');
}
