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
  'yutub': 'com.google.android.youtube',
  'chrome': 'com.android.chrome',
  'krom': 'com.android.chrome',
  'browser': 'com.android.chrome',
  'kamera': 'com.android.camera',
  'camera': 'com.android.camera',
  'galeri': 'com.google.android.apps.photos',
  'foto': 'com.google.android.apps.photos',
  'maps': 'com.google.android.apps.maps',
  'map': 'com.google.android.apps.maps',
  'gmaps': 'com.google.android.apps.maps',
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
  'tele': 'org.telegram.messenger',
  'shopee': 'com.shopee.id',
  'sopi': 'com.shopee.id',
  'shopi': 'com.shopee.id',
  'tokopedia': 'com.tokopedia.tkpd',
  'toped': 'com.tokopedia.tkpd',
  'dana': 'id.dana',
  'ovo': 'ovo.id',
  'gopay': 'com.gojek.gopay',
  'gojek': 'com.gojek.app',
  'grab': 'com.grabtaxi.passenger',
  'mobile legend': 'com.mobile.legends',
  'ml': 'com.mobile.legends',
  'mlbb': 'com.mobile.legends',
  'free fire': 'com.dts.freefireth',
  'ff': 'com.dts.freefireth',
  'epep': 'com.dts.freefireth',
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
  // (layar/hp/hape/alarm/chat/senter/lampu dikecualikan: perintah lain)
  if (has(['buka', 'bukain', 'bukakan', 'open', 'jalankan', 'nyalain', 'idupin', 'hidupin']) &&
      !has(['layar', 'hp', 'hape', 'handphone', 'alarm', 'chat', 'senter', 'lampu'])) {
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
      action: () async {
        final r = await AppController.openApp(kw);
        // Native menemukan yang mirip -> ucapkan namanya dengan benar.
        if (r.startsWith('OK_MAKSUD:')) {
          return 'SAY:Maksudnya ${r.substring('OK_MAKSUD:'.length)} ya Sir. Membuka.';
        }
        return r;
      },
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

  // --- TELEPON: "telpon 0812..." / "telpon mama" (buka dialer terisi) ---
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
    final nama = t
        .replaceFirst(RegExp(r'^(telpon|telepon|call|hubungi)\s+'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (nama.length >= 2) {
      return ParsedCommand(
        handledLocally: true,
        reply: 'Mencari kontak $nama, Sir.',
        action: () async {
          final perm = await AppController.requestContacts();
          if (perm != 'OK') return 'SAY:$perm';
          final found = await AppController.resolveContact(nama);
          if (found.startsWith('NONE:')) {
            return 'SAY:Kontak $nama tidak ketemu di HP, Sir.';
          }
          if (found.startsWith('DENIED:')) {
            return 'SAY:${found.substring('DENIED:'.length)}';
          }
          final sep = found.indexOf('|');
          final num = found.substring(0, sep);
          final label = found.substring(sep + 1);
          final r = await AppController.dial(num);
          if (r != 'OK') return 'SAY:$r';
          return 'SAY:Membuka dialer $label, Sir. Tap panggil.';
        },
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

  // --- CHAT WA: "buka wa chat mama" / "wa ke 0812 halo bro" ---
  // Nama kontak dicari di HP (butuh izin kontak), nomor langsung gas.
  // (Blok ini SEBELUM blok SMS agar "chat" tidak nyasar.
  //  "buka chat X" tanpa kata wa pun dianggap WA: paling umum di Indonesia.)
  if ((has(['wa', 'whatsapp']) || has(['buka chat', 'open chat'])) &&
      !has(['layar', 'senter', 'lampu']) &&
      has(['chat', 'pesan', 'kirim', 'ke', 'tulis'])) {
    // Ambil nama/nomor: buang kata perintah berulang-ulang.
    var rest = s
        .replaceFirst(RegExp(r'^(buka|bukain|tolong|dong|coba)\s+'), '')
        .replaceAll(RegExp(r'\b(wa|whatsapp)\b'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    for (var i = 0; i < 3; i++) {
      final next = rest
          .replaceFirst(RegExp(r'^(ke|chat|pesan|kirim|tulis)\s+'), '')
          .trim();
      if (next == rest) break;
      rest = next;
    }
    // Pisahkan pesan: "... pesannya halo" -> nama + isi.
    var body = '';
    final bodyM =
        RegExp(r'(pesannya|isinya|\bpesan\b)\s+(.+)').firstMatch(rest);
    if (bodyM != null) {
      body = bodyM.group(2)!.trim();
      rest = rest.replaceFirst(bodyM.group(0)!, '').trim();
    }
    final digits =
        RegExp(r'\+?\d[\d ]{5,}').firstMatch(rest)?.group(0) ?? '';
    if (digits.replaceAll(RegExp(r'\D'), '').length >= 6) {
      final num = digits;
      return ParsedCommand(
        handledLocally: true,
        reply: 'Membuka chat WA, Sir.',
        action: () => AppController.openWaChat(num, body),
      );
    }
    if (rest.length >= 2) {
      final nama = rest;
      return ParsedCommand(
        handledLocally: true,
        reply: 'Mencari kontak $nama, Sir.',
        action: () async {
          final perm = await AppController.requestContacts();
          if (perm != 'OK') return 'SAY:$perm';
          final found = await AppController.resolveContact(nama);
          if (found.startsWith('NONE:')) {
            return 'SAY:Kontak $nama tidak ketemu di HP, Sir. Coba nama lain.';
          }
          if (found.startsWith('DENIED:')) {
            return 'SAY:${found.substring('DENIED:'.length)}';
          }
          final sep = found.indexOf('|');
          final num = found.substring(0, sep);
          final label = found.substring(sep + 1);
          final r = await AppController.openWaChat(num, body);
          if (r != 'OK') return 'SAY:$r';
          return 'SAY:Membuka chat $label, Sir.';
        },
      );
    }
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

  // --- PENGATURAN SUARA TTS ---
  if (t.contains('setting suara') ||
      t.contains('pengaturan suara') ||
      t.contains('suara google') ||
      t.contains('install suara') ||
      t == 'tts') {
    return ParsedCommand(
      handledLocally: true,
      reply: 'Membuka pengaturan suara. Install paket Indonesia agar offline tetap bersuara, Sir.',
      action: () => AppController.openSettingsPage('tts'),
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

  // --- KALKULATOR SUARA (100% offline): "berapa 12 kali 3 tambah 5" ---
  if ((s.startsWith('berapa') || s.startsWith('hitung')) &&
      RegExp(r'\d').hasMatch(s)) {
    final hitung = _hitung(s);
    if (hitung != null) {
      return ParsedCommand(
        handledLocally: true,
        reply: 'Hasilnya $hitung, Sir.',
      );
    }
    // Tidak bisa diparse -> biarkan Groq yang coba (tetap offline-safe).
  }

  // --- RUTIN (gabungan aksi, 100% offline): mode tidur/kerja/nonton ---
  if (has(['mode tidur', 'selamat tidur', 'mau tidur'])) {
    return ParsedCommand(
      handledLocally: true,
      reply: 'Mode tidur, Sir.',
      action: () async {
        await AppController.ringerMode('silent');
        final r = await AppController.lockScreen();
        return r == 'OK' ? 'SAY:Mode tidur, Sir. HP hening + terkunci.' : 'SAY:$r';
      },
    );
  }
  if (has(['mode kerja'])) {
    return ParsedCommand(
      handledLocally: true,
      reply: 'Mode kerja, Sir.',
      action: () async {
        await AppController.ringerMode('normal');
        await AppController.openApp('com.google.android.gm');
        return 'SILENT:0|Mode kerja, Sir. Suara normal + Gmail dibuka.';
      },
    );
  }
  if (has(['mode nonton', 'mode film', 'mode bioskop'])) {
    return ParsedCommand(
      handledLocally: true,
      reply: 'Mode nonton, Sir.',
      action: () async {
        await AppController.ringerMode('vibrate');
        await AppController.openApp('com.google.android.youtube');
        // SILENT:1 = Jarvis ikut bisu agar video tidak keganggu.
        return 'SILENT:1|Mode nonton, Sir. Saya diam sampai mode suara dinyalakan.';
      },
    );
  }

  // --- PENGINGAT: "ingatkan minum obat dalam 10 menit" / "... jam 7 pagi" ---
  if (s.startsWith('ingatkan ') || s.startsWith('ingetin ')) {
    final rem = _parseReminder(s);
    if (rem == null) {
      return ParsedCommand(
        handledLocally: true,
        reply:
            'Sir, contohnya: ingatkan minum obat dalam 10 menit. Atau: ingatkan rapat jam 7 pagi.',
      );
    }
    final at = rem['at'] as int;
    final body = rem['text'] as String;
    return ParsedCommand(
      handledLocally: true,
      reply: 'Memasang pengingat, Sir.',
      action: () async {
        final id = DateTime.now().millisecondsSinceEpoch;
        final r = await AppController.setReminder(id, at, body);
        if (r != 'OK') return 'SAY:$r';
        final sp = await SharedPreferences.getInstance();
        final list = sp.getStringList('jarvis_reminders') ?? [];
        list.add('$id|$at|$body');
        await sp.setStringList('jarvis_reminders', list);
        final when = DateTime.fromMillisecondsSinceEpoch(at);
        final hh = when.hour.toString().padLeft(2, '0');
        final mm = when.minute.toString().padLeft(2, '0');
        return 'SAY:Siap Sir, diingatkan "$body" jam $hh lewat $mm.';
      },
    );
  }
  if (has(['lihat pengingat', 'baca pengingat', 'daftar pengingat'])) {
    return ParsedCommand(
      handledLocally: true,
      reply: 'Mengecek pengingat, Sir.',
      action: () async {
        final sp = await SharedPreferences.getInstance();
        final list = sp.getStringList('jarvis_reminders') ?? [];
        final now = DateTime.now().millisecondsSinceEpoch;
        final aktif =
            list.where((e) => (int.tryParse(e.split('|').first) ?? 0) > 0).toList();
        if (aktif.isEmpty) return 'SAY:Tidak ada pengingat aktif, Sir.';
        final isi = aktif.map((e) {
          final p = e.split('|');
          final when =
              DateTime.fromMillisecondsSinceEpoch(int.tryParse(p[1]) ?? now);
          final hh = when.hour.toString().padLeft(2, '0');
          final mm = when.minute.toString().padLeft(2, '0');
          return '${p.length > 2 ? p.sublist(2).join('|') : ''} jam $hh:$mm';
        }).join('. ');
        return 'SAY:Pengingat Sir: $isi.';
      },
    );
  }
  if (has(['hapus pengingat', 'batal pengingat'])) {
    return ParsedCommand(
      handledLocally: true,
      reply: 'Menghapus pengingat, Sir.',
      action: () async {
        final sp = await SharedPreferences.getInstance();
        final list = sp.getStringList('jarvis_reminders') ?? [];
        for (final e in list) {
          final id = int.tryParse(e.split('|').first) ?? 0;
          if (id > 0) await AppController.cancelReminder(id);
        }
        await sp.remove('jarvis_reminders');
        return 'SAY:Semua pengingat dihapus, Sir.';
      },
    );
  }

  // --- LIHAT LAYAR: AI membaca screenshot ("lihat layar") ---
  if (has([
    'lihat layar', 'baca layar', 'apa yang tampil', 'apa di layar',
    'jelaskan layar'
  ])) {
    return ParsedCommand(
      handledLocally: true,
      reply: 'Melihat layar, Sir.',
      action: () async {
        final shot = await AppController.screenshot();
        if (shot.startsWith('ERR:')) {
          return 'SAY:${shot.substring('ERR:'.length)}';
        }
        return 'VISION:$shot';
      },
    );
  }

  // --- TANGKAP LAYAR ke galeri ("screenshot", "ss") ---
  if (has(['tangkap layar', 'screenshot', 'ambil screenshot']) ||
      s == 'ss' ||
      s.startsWith('ss ')) {
    return ParsedCommand(
      handledLocally: true,
      reply: 'Menangkap layar, Sir.',
      action: () async {
        final r = await AppController.saveShot();
        if (r.startsWith('OK:')) return 'SAY:${r.substring(3)}';
        if (r.startsWith('ERR:')) return 'SAY:${r.substring(4)}';
        return 'SAY:$r';
      },
    );
  }

  // --- REKAM LAYAR ("rekam layar", "stop rekam") ---
  if (has(['rekam layar', 'mulai rekam', 'merekam layar'])) {
    return ParsedCommand(
      handledLocally: true,
      reply: 'Menyiapkan rekaman, Sir. Izinkan di dialog yang muncul.',
      action: () async {
        final r = await AppController.startRecording();
        if (r.startsWith('BATAL:')) return 'SAY:${r.substring(6)}';
        if (r.startsWith('OK:')) return 'SAY:${r.substring(3)}';
        return 'SAY:$r';
      },
    );
  }
  if (has(['stop rekam', 'setop rekam', 'berhenti rekam', 'berhenti merekam',
      'selesai rekam'])) {
    return ParsedCommand(
      handledLocally: true,
      reply: 'Menghentikan rekaman, Sir.',
      action: () async {
        final r = await AppController.stopRecording();
        if (r.startsWith('TIDAK_MEREKAM:')) {
          return 'SAY:${r.substring('TIDAK_MEREKAM:'.length)}';
        }
        if (r.startsWith('OK:')) return 'SAY:${r.substring(3)}';
        return 'SAY:$r';
      },
    );
  }

  // --- WIFI ("nyalakan wifi", "matikan wifi") ---
  if (has(['wifi', 'wi-fi'])) {
    final on = !(has(['mati', 'matikan', 'matiin', 'off']));
    return ParsedCommand(
      handledLocally: true,
      reply: on ? 'Mengurus WiFi, Sir.' : 'Mematikan WiFi, Sir.',
      action: () => AppController.setWifi(on),
    );
  }

  // --- BLUETOOTH ("nyalakan bluetooth", "matikan bluetooth") ---
  if (has(['bluetooth', 'blutut', 'blututh'])) {
    // Bukan buka halaman setting (itu sudah ada) -> toggle nyala/mati.
    if (has(['pengaturan', 'setting'])) {
      return ParsedCommand(
        handledLocally: true,
        reply: 'Membuka pengaturan Bluetooth, Sir.',
        action: () => AppController.openSettingsPage('bluetooth'),
      );
    }
    final on = !(has(['mati', 'matikan', 'matiin', 'off']));
    return ParsedCommand(
      handledLocally: true,
      reply: on ? 'Menyalakan Bluetooth, Sir.' : 'Mematikan Bluetooth, Sir.',
      action: () async {
        final p = await AppController.requestBt();
        if (p != 'OK') return 'SAY:$p';
        final r = await AppController.setBluetooth(on);
        if (r.startsWith('NEED_BT:')) {
          return 'SAY:${r.substring('NEED_BT:'.length)}';
        }
        return r;
      },
    );
  }

  // --- FOTO ("foto", "selfie") ---
  if (s == 'foto' ||
      s.startsWith('foto ') ||
      s.contains('ambil foto') ||
      s.contains('selfie') ||
      s.contains('foto selfie')) {
    final front = s.contains('selfie') || s.contains('depan');
    return ParsedCommand(
      handledLocally: true,
      reply: 'Membuka kamera, Sir.',
      action: () => AppController.takePhoto(front),
    );
  }

  // --- BRIEFING PAGI (jam + tanggal + baterai, 100% offline) ---
  if (has(['briefing', 'laporan pagi', 'info pagi', 'ringkasan pagi'])) {
    return ParsedCommand(
      handledLocally: true,
      reply: 'Menyiapkan briefing, Sir.',
      action: () async {
        const hari = [
          'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'
        ];
        const bulan = [
          '', 'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
          'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
        ];
        final now = DateTime.now();
        final hh = now.hour.toString().padLeft(2, '0');
        final mm = now.minute.toString().padLeft(2, '0');
        var bat = '';
        try {
          final r = await AppController.getBattery();
          final m = RegExp(r'BATERAI:(\d+)').firstMatch(r);
          if (m != null) bat = ', baterai ${m.group(1)} persen';
        } catch (_) {}
        return 'SAY:Selamat pagi Sir. Hari ${hari[now.weekday - 1]}, '
            '${now.day} ${bulan[now.month]} ${now.year}, jam $hh lewat $mm$bat. '
            'Ada yang bisa saya bantu?';
      },
    );
  }

  // --- LAWAKAN receh (100% offline) ---
  if (has(['lawak', 'lucu', 'humor', 'guyon', 'ketawa'])) {
    const jokes = [
      'Kenapa programmer benci alam? Karena terlalu banyak bug, Sir.',
      'Kenapa HP tidak pernah bohong? Karena selalu ada sinyal kebenaran, Sir.',
      'Apa bedanya Sir dengan WiFi? WiFi kadang hilang, Sir selalu ada buat saya.',
      'Kenapa baterai optimis? Karena selalu berpikir positif dan negatif sekaligus, Sir.',
      'Saya mau cuti Sir... tapi saya tinggal di HP ini.',
    ];
    final pick =
        jokes[DateTime.now().millisecond % jokes.length];
    return ParsedCommand(handledLocally: true, reply: '$pick');
  }

  // --- Bukan perintah lokal -> lempar ke Groq AI (butuh internet) ---
  return ParsedCommand(handledLocally: false, reply: '');
}

/// Parse "ingatkan X dalam N menit/jam" atau "ingatkan X jam H[:M] pagi..".
/// Return {'at': millis, 'text': ...} atau null.
Map<String, dynamic>? _parseReminder(String s) {
  var rest = s
      .replaceFirst(RegExp(r'^(ingatkan|ingetin)\s+'), '')
      .trim();
  if (rest.isEmpty) return null;
  final now = DateTime.now();
  // Pola 1: ... dalam 10 menit / 2 jam
  final dalam =
      RegExp(r'dalam\s+(\d+)\s*(menit|mnt|jam)').firstMatch(rest);
  if (dalam != null) {
    final n = int.parse(dalam.group(1)!);
    final unit = dalam.group(2)!;
    final at = now.add(
        unit.startsWith('jam') ? Duration(hours: n) : Duration(minutes: n));
    final body = rest.replaceFirst(dalam.group(0)!, '').trim();
    if (body.isEmpty) return null;
    return {'at': at.millisecondsSinceEpoch, 'text': _cap(body)};
  }
  // Pola 2: ... jam 7 [pagi/siang/sore/malam] / jam 7:30
  final jam =
      RegExp(r'jam\s+(\d{1,2})(?:[:.](\d{2}))?\s*(pagi|siang|sore|malam)?')
          .firstMatch(rest);
  if (jam != null) {
    var h = int.parse(jam.group(1)!);
    final m = jam.group(2) != null ? int.parse(jam.group(2)!) : 0;
    final suf = jam.group(3) ?? '';
    if ((suf == 'siang' || suf == 'sore' || suf == 'malam') && h < 12) {
      h += 12;
    }
    if (suf == 'pagi' && h == 12) h = 0;
    if (h > 23 || m > 59) return null;
    var at = DateTime(now.year, now.month, now.day, h, m);
    if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
    final body = rest.replaceFirst(jam.group(0)!, '').trim();
    if (body.isEmpty) return null;
    return {'at': at.millisecondsSinceEpoch, 'text': _cap(body)};
  }
  return null;
}

String _cap(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Evaluator aritmetika mini (+ - * / dan kurung, koma desimal).
/// Return hasil format Indonesia, atau null bila tak bisa diparse.
String? _hitung(String s) {
  try {
    var e = s
        .replaceFirst(RegExp(r'^(berapa|hitung)\s+'), '')
        .replaceAll('tambah', '+')
        .replaceAll('plus', '+')
        .replaceAll('kurang', '-')
        .replaceAll('minus', '-')
        .replaceAll('kali', '*')
        .replaceAll('perkalian', '*')
        .replaceAll('bagi', '/')
        .replaceAll('dibagi', '/')
        .replaceAll('persen', '/100')
        .replaceAll('%', '/100')
        .replaceAll('koma', '.')
        .replaceAll('x', '*')
        .replaceAll('×', '*')
        .replaceAll('÷', '/');
    e = e.replaceAll(RegExp(r'[^0-9+\-*/.() ]'), ' ').trim();
    if (!RegExp(r'\d').hasMatch(e)) return null;
    final v = _Calc(e).run();
    if (v.isInfinite || v.isNaN) return null;
    var out = v.toStringAsFixed(v.truncateToDouble() == v ? 0 : 2);
    return out.replaceAll('.', ',');
  } catch (_) {
    return null;
  }
}

/// Parser aritmetika mini (+ - * / dan kurung). Class agar method
/// bisa saling memanggil (fungsi lokal Dart tak boleh forward-reference).
class _Calc {
  final List<String> toks;
  int pos = 0;

  _Calc(String e)
      : toks = RegExp(r'\d+\.?\d*|[+\-*/()]')
            .allMatches(e.replaceAll(' ', ''))
            .map((m) => m.group(0)!)
            .toList();

  double run() {
    final v = expr();
    if (pos != toks.length) throw const FormatException('sisa token');
    return v;
  }

  double expr() {
    var v = term();
    while (pos < toks.length && (toks[pos] == '+' || toks[pos] == '-')) {
      final op = toks[pos++];
      final r = term();
      v = op == '+' ? v + r : v - r;
    }
    return v;
  }

  double term() {
    var v = factor();
    while (pos < toks.length && (toks[pos] == '*' || toks[pos] == '/')) {
      final op = toks[pos++];
      final r = factor();
      v = op == '*' ? v * r : v / r;
    }
    return v;
  }

  double factor() {
    if (pos < toks.length && toks[pos] == '-') {
      pos++;
      return -factor();
    }
    if (pos < toks.length && toks[pos] == '(') {
      pos++;
      final v = expr();
      if (pos < toks.length && toks[pos] == ')') pos++;
      return v;
    }
    return double.parse(toks[pos++]);
  }
}
