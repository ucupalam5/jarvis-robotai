import 'package:shared_preferences/shared_preferences.dart';

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

  // Normalisasi gaya Jakarta + salah-dengar STT ("nya lain" -> "nyalain"):
  // - buang kata pengisi di awal (tolong, coba, eh, woi, bang)
  // - versi tanpa spasi untuk pencocokan longgar
  final s = t
      .replaceAll(
          RegExp(r'^(tolong|tolongin|coba|eh+|woi|woy|bang|min)\s+'), '')
      .trim();
  final c = s.replaceAll(RegExp(r'\s+'), '');

  bool has(List<String> keys) {
    for (final k in keys) {
      if (s.contains(k)) return true;
      final kc = k.replaceAll(' ', '');
      if (kc.isNotEmpty && c.contains(kc)) return true;
    }
    return false;
  }

  // --- BUKA APLIKASI: "buka whatsapp", "nyalain spotify", "bukain ig dong" ---
  // (layar/hp/hape/senter/lampu dikecualikan: itu perintah daya, BUKAN app)
  if (has(['buka', 'bukain', 'bukakan', 'open', 'jalankan', 'nyalain', 'idupin', 'hidupin']) &&
      !has(['layar', 'hp', 'hape', 'handphone', 'senter', 'lampu'])) {
    String target = s
        .replaceAll(
            RegExp(r'(tolong|dong|coba|buka|bukain|bukakan|open|jalankan|nyalain|nyalakain|idupin|hidupin)'),
            '')
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
  // Nyalakan via WakeLock + coba swipe buka kunci geser.
  // PIN/fingerprint tetap manual (blokir keamanan Android).
  if (has([
    'nyalakan layar', 'nyalakan hp', 'nyalakan hape',
    'nyalain layar', 'nyalain hp', 'nyalain hape',
    'idupin layar', 'idupin hp', 'idupin hape',
    'hidupkan layar', 'hidupkan hp', 'hidupkan hape',
    'bangun', 'wake up'
  ])) {
    return ParsedCommand(
      handledLocally: true,
      reply: 'Menyalakan layar, Sir.',
      action: () async {
        await AppController.wakeUp();
        await Future.delayed(const Duration(milliseconds: 900));
        return AppController.accSwipeUp();
      },
    );
  }

  // --- TAP TOMBOL KIRIM (misal tombol Kirim WA): cari label, fallback tap.
  if (t.contains('tap kirim') ||
      t.contains('tekan kirim') ||
      t.contains('klik kirim') ||
      t.contains('kirim pesan ini')) {
    return ParsedCommand(
      handledLocally: true,
      reply: 'Menekan tombol kirim, Sir.',
      action: () async {
        final r = await AppController.accClickSend();
        if (r == 'OK') return 'OK';
        return AppController.accTap(935, 950);
      },
    );
  }

  // --- KETIK OTOMATIS: "ketik halo bro" (ke kolom chat yang fokus) ---
  if (t.startsWith('ketik ') || t.startsWith('ketikkan ')) {
    final txt =
        rawText.replaceFirst(RegExp(r'(?i)^(ketik|ketikkan)\s+'), '').trim();
    if (txt.isEmpty) {
      return ParsedCommand(
          handledLocally: true, reply: 'Mau ketik apa, Sir?');
    }
    return ParsedCommand(
      handledLocally: true,
      reply: 'Mengetik ke kolom chat, Sir. Tap kolom dulu bila gagal.',
      action: () => AppController.accType(txt),
    );
  }

  // --- BATERAI: "baterai berapa" ---
  if (t.contains('baterai') || t.contains('battery') || t.contains('batre')) {
    return ParsedCommand(
      handledLocally: true,
      reply: 'Mengecek baterai, Sir.',
      action: () async {
        final r = await AppController.getBattery();
        // Format native: BATERAI:85:1
        final m = RegExp(r'BATERAI:(\d+):(\d)').firstMatch(r);
        if (m != null) {
          final pct = m.group(1);
          final chg = m.group(2) == '1' ? ' dan sedang mengisi daya' : '';
          return 'BATERAI_REPLY:Baterai tersisa $pct persen$chg, Sir.';
        }
        return r;
      },
    );
  }

  // --- JAM / TANGGAL (murni Dart, tanpa native) ---
  if (t.contains('jam berapa') || t == 'jam' || t.contains('pukul berapa')) {
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return ParsedCommand(
      handledLocally: true,
      reply: 'Sekarang jam $hh lewat $mm, Sir.',
    );
  }
  if (t.contains('tanggal berapa') ||
      t.contains('hari apa') ||
      t.contains('tanggal hari ini')) {
    const hari = [
      'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'
    ];
    const bulan = [
      '', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
      'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
    ];
    final now = DateTime.now();
    return ParsedCommand(
      handledLocally: true,
      reply:
          'Hari ini ${hari[now.weekday - 1]}, tanggal ${now.day} ${bulan[now.month]} ${now.year}, Sir.',
    );
  }

  // --- ALARM: "pasang alarm jam 6 pagi" / "alarm jam 7 malam" ---
  if (t.contains('alarm')) {
    final num = RegExp(r'(\d{1,2})(?:[:.](\d{2}))?').firstMatch(t);
    if (num != null) {
      var h = int.parse(num.group(1)!);
      var m = num.group(2) != null ? int.parse(num.group(2)!) : 0;
      if (t.contains('siang') || t.contains('sore') || t.contains('malam')) {
        if (h < 12) h += 12;
        if (h == 24) h = 12;
      }
      if (h > 23 || m > 59) {
        return ParsedCommand(
            handledLocally: true, reply: 'Jam alarm tidak valid, Sir.');
      }
      final hh = h;
      final mm = m;
      final label =
          'Jarvis ${hh.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
      return ParsedCommand(
        handledLocally: true,
        reply: 'Siap Sir, membuka jam untuk alarm $label.',
        action: () => AppController.setAlarm(hh, mm, label),
      );
    }
    return ParsedCommand(
      handledLocally: true,
      reply: 'Sir, jam berapa alarmnya? Contoh: pasang alarm jam 6 pagi.',
    );
  }

  // --- TELEPON: "telpon 0812..." (buka dialer, tanpa izin CALL_PHONE) ---
  if (t.startsWith('telpon') ||
      t.startsWith('telepon') ||
      t.startsWith('call ') ||
      t.contains('hubungi ')) {
    final digits = RegExp(r'\+?\d[\d ]{5,}').firstMatch(t)?.group(0) ?? '';
    if (digits.replaceAll(RegExp(r'\D'), '').length >= 6) {
      return ParsedCommand(
        handledLocally: true,
        reply: 'Membuka dialer, Sir.',
        action: () => AppController.dial(digits),
      );
    }
    return ParsedCommand(
      handledLocally: true,
      reply: 'Sir, nomornya berapa? Contoh: telpon 081234567890.',
    );
  }

  // --- SMS: "sms ke 0812 pesannya halo" ---
  if (t.startsWith('sms') || t.contains('kirim sms')) {
    final numM = RegExp(r'(\+?\d[\d ]{5,})').firstMatch(t);
    final bodyM = RegExp(r'(pesannya|isinya|pesan)\s+(.+)').firstMatch(t);
    final num = numM?.group(1) ?? '';
    final body = bodyM?.group(2) ?? 'Halo, ini Jarvis Sir.';
    if (num.replaceAll(RegExp(r'\D'), '').length >= 6) {
      return ParsedCommand(
        handledLocally: true,
        reply: 'Membuka SMS, Sir. Tinggal tap kirim.',
        action: () => AppController.sms(num, body),
      );
    }
    return ParsedCommand(
      handledLocally: true,
      reply: 'Sir, contohnya: sms ke 081234567890 pesannya halo bro.',
    );
  }

  // --- CARI GOOGLE: "cari resep rendang" / "search ..." ---
  if (t.startsWith('cari ') || t.startsWith('carikan ') || t.startsWith('search ')) {
    final q = t
        .replaceFirst(RegExp(r'^(cari|carikan|search)\s+'), '')
        .replaceAll(RegExp(r'\s+di google\s*$'), '')
        .trim();
    return ParsedCommand(
      handledLocally: true,
      reply: 'Mencari $q di Google, Sir.',
      action: () => AppController.webSearch(q),
    );
  }

  // --- PENGATURAN CEPAT: "pengaturan wifi" ---
  if (t.contains('wifi')) {
    return ParsedCommand(
      handledLocally: true,
      reply: 'Membuka pengaturan WiFi, Sir.',
      action: () => AppController.openSettingsPage('wifi'),
    );
  }
  if (t.contains('bluetooth') || t.contains('blutut')) {
    return ParsedCommand(
      handledLocally: true,
      reply: 'Membuka pengaturan Bluetooth, Sir.',
      action: () => AppController.openSettingsPage('bluetooth'),
    );
  }

  // --- DAFTAR APLIKASI: bantu yang susah cari app ---
  if (has(['daftar aplikasi', 'list aplikasi', 'semua aplikasi', 'cari aplikasi'])) {
    return ParsedCommand(
      handledLocally: true,
      reply: 'Membuka daftar aplikasi, Sir. Ketik cari + tap untuk buka.',
      action: () async => 'SHOW_APPS:',
    );
  }

  // --- MODE DERING HP: getar / hening / normal ---
  if (has(['mode getar']) || (s == 'getar' || s.contains('jadi getar'))) {
    return ParsedCommand(
      handledLocally: true,
      reply: 'HP mode getar, Sir.',
      action: () => AppController.ringerMode('vibrate'),
    );
  }
  if (has(['mode hening', 'mode diam']) || s == 'hening') {
    return ParsedCommand(
      handledLocally: true,
      reply: 'HP mode hening, Sir.',
      action: () => AppController.ringerMode('silent'),
    );
  }
  if (has(['mode normal', 'mode dering', 'mode bunyi', 'mode nyala'])) {
    return ParsedCommand(
      handledLocally: true,
      reply: 'HP mode normal, Sir.',
      action: () => AppController.ringerMode('normal'),
    );
  }

  // --- MUSIK: jeda / main / lagu berikutnya / sebelumnya ---
  if (has(['musik jeda', 'musik pause', 'jeda musik', 'pause musik', 'berhenti musik'])) {
    return ParsedCommand(
      handledLocally: true,
      reply: 'Musik dijeda, Sir.',
      action: () => AppController.mediaKey(127),
    );
  }
  if (has(['musik main', 'lanjut musik', 'main musik', 'putar musik'])) {
    return ParsedCommand(
      handledLocally: true,
      reply: 'Musik main, Sir.',
      action: () => AppController.mediaKey(126),
    );
  }
  if (has(['lagu berikutnya', 'lagu selanjutnya', 'next lagu', 'ganti lagu'])) {
    return ParsedCommand(
      handledLocally: true,
      reply: 'Lagu berikutnya, Sir.',
      action: () => AppController.mediaKey(87),
    );
  }
  if (has(['lagu sebelumnya', 'lagu tadi', 'kembali lagu', 'putar ulang'])) {
    return ParsedCommand(
      handledLocally: true,
      reply: 'Kembali ke lagu sebelumnya, Sir.',
      action: () => AppController.mediaKey(88),
    );
  }

  // --- KUNCI / MATIKAN LAYAR (senter/lampu dikecualikan) ---
  final mauKunci = has(['kunci', 'matiin', 'matikan']) &&
      has(['layar', 'hp', 'hape', 'handphone']);
  if ((mauKunci || has(['lock'])) &&
      !has(['senter', 'lampu'])) {
    return ParsedCommand(
      handledLocally: true,
      reply: 'Mengunci layar sekarang, Sir.',
      action: () => AppController.lockScreen(),
    );
  }

  // --- SENTER ---
  if (has(['senter', 'flashlight', 'lampu'])) {
    final on = !has(['mati']);
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

  // --- CATATAN SUARA: "catat beli susu" / "baca catatan" / "hapus catatan" ---
  if (t.startsWith('catat ')) {
    final body =
        rawText.replaceFirst(RegExp(r'(?i)^catat\s+'), '').trim();
    if (body.isEmpty) {
      return ParsedCommand(
          handledLocally: true, reply: 'Mau catat apa, Sir?');
    }
    return ParsedCommand(
      handledLocally: true,
      reply: 'Mencatat, Sir.',
      action: () async {
        final sp = await SharedPreferences.getInstance();
        final list = sp.getStringList('jarvis_notes') ?? [];
        list.add(body);
        await sp.setStringList('jarvis_notes', list);
        return 'SAY:Dicatat, Sir: $body. Total ${list.length} catatan.';
      },
    );
  }
  if (t.contains('baca catatan') || t.contains('lihat catatan')) {
    return ParsedCommand(
      handledLocally: true,
      reply: 'Membaca catatan, Sir.',
      action: () async {
        final sp = await SharedPreferences.getInstance();
        final list = sp.getStringList('jarvis_notes') ?? [];
        if (list.isEmpty) return 'SAY:Belum ada catatan, Sir.';
        final isi = list
            .asMap()
            .entries
            .map((e) => '${e.key + 1}. ${e.value}')
            .join('. ');
        return 'SAY:Catatan Sir: $isi.';
      },
    );
  }
  if (t.contains('hapus catatan') || t.contains('hapus semua catatan')) {
    return ParsedCommand(
      handledLocally: true,
      reply: 'Menghapus catatan, Sir.',
      action: () async {
        final sp = await SharedPreferences.getInstance();
        await sp.remove('jarvis_notes');
        return 'SAY:Semua catatan dihapus, Sir.';
      },
    );
  }

  // --- Bukan perintah lokal -> lempar ke Groq AI ---
  return ParsedCommand(handledLocally: false, reply: '');
}
