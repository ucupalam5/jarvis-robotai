# JARVIS RobotAI - Asisten Pribadi Android ala Iron Man

Aplikasi Flutter + Groq AI (gratis) + Voice (Indonesia) + Popup Overlay + Kontrol HP via suara.

## Fitur

- Tap orb -> bicara Indonesia -> Jarvis menjawab via suara + teks
- Perintah lokal (offline, cepat):
  - "buka whatsapp / youtube / ig / tiktok / kamera / pengaturan ..." (buka aplikasi apapun)
  - "tutup aplikasi" (via Accessibility + finish task)
  - "kembali ke home"
  - "kunci layar / matikan layar / matikan hp" (via Device Admin)
  - "nyalakan/matikan senter"
  - "volume naik / turun"
  - "ingatkan minum obat jam 7 pagi" — kalau jamnya tidak jelas, Jarvis **tanya balik** (slot-filling) lalu memasang pengingat
  - "briefing pagi" — jam + tanggal + baterai + **cuaca hari ini (Open-Meteo, gratis)** + pengingat hari ini
  - **Skill TradingView**: "harga bitcoin berapa?" / "harga saham bbca" — harga kripto real-time (Binance, gratis) + saham IDX (Stooq, gratis), dibacakan via suara. "buka tradingview" membuka aplikasinya.
- Selain itu -> dijawab Groq AI gaya Jarvis Indonesia campur Inggris, dengan **function calling**: AI bisa mengeksekusi aksi (pasang pengingat/alarm, buka aplikasi, cek cuaca/baterai/jam, cek harga kripto/saham), bukan cuma menjawab teks
- Popup RobotAI melayang di atas aplikasi lain (tombol overlay di AppBar)
- Simpan Groq API key di Settings (SharedPreferences)
- SMS darurat find-my-phone: kode + **allowlist nomor tepercaya** (opsional, di Settings)

## Otak AI

Groq (gratis), model utama `openai/gpt-oss-20b` dengan fallback otomatis ke `openai/gpt-oss-120b` lalu `qwen/qwen3.6-27b` bila model pensiun (404) atau kuota habis (429). Vision via `meta-llama/llama-4-maverick-17b-128e-instruct` / `llama-4-scout-17b-16e-instruct`.

## Jujur soal batasan Android (penting!)

1. **Nyalakan HP dari mati total = TIDAK BISA via aplikasi.** Itu butuh tombol power (hardware). Yang bisa: kunci layar, matikan layar, sleep, restart (root).
2. **Tutup aplikasi lain di Android 10+ dibatasi Google.** Solusi di app ini: AccessibilityService + finishAndRemoveTask + BACK/HOME. Aktifkan di Settings > Accessibility > Jarvis.
3. **Popup overlay butuh izin SYSTEM_ALERT_WINDOW.** Sudah diminta otomatis saat tap tombol overlay.
4. **Kunci layar butuh Device Admin.** Akan diminta sekali, aktifkan.
5. **Otomatisasi tap/ketik (mis. kirim WA otomatis) memakai AccessibilityService**, bukan Shizuku. Koordinat tap bisa beda tiap HP — uji di HP sendiri.

## Struktur

```
lib/
  main.dart
  core/groq_service.dart       -> otak Groq + function calling
  core/voice_service.dart      -> STT id-ID + TTS id-ID (sanitasi markdown)
  core/command_parser.dart     -> "buka...", "kunci layar", ..., slot-filling
  core/app_controller.dart     -> MethodChannel jarvis/control
  core/memory_service.dart     -> memori permanen ("inget ya ...")
  core/overlay_service.dart    -> config popup
  core/update_service.dart     -> cek update GitHub Release (versi otomatis)
  core/weather_service.dart    -> cuaca Open-Meteo (gratis, tanpa key)
  core/market_service.dart     -> skill TradingView: harga kripto (Binance) + saham IDX (Stooq), gratis tanpa key
  ui/home_screen.dart          -> layar utama + chat + settings
  ui/jarvis_orb.dart           -> animasi orb reactor
  ui/onboarding.dart
  ui/power_screen.dart         -> Pusat Kekuasaan (16 izin)
android/.../MainActivity.kt    -> ~90 method native: openApp, closeApp, lock, flash, volume, ...
android/.../SmsReceiver.kt     -> SMS SOS find-my-phone (+ allowlist nomor)
android/.../TgPollService.kt   -> remote via Telegram (FIND/RING/LOCK/SHOT/...)
```

## API Key Groq Gratis

1. Buka https://console.groq.com -> Login -> API Keys -> Create
2. Copy `gsk_...` -> buka app -> ikon Settings -> paste -> Save
3. Key disimpan di SharedPreferences HP (tidak memakai file .env)
