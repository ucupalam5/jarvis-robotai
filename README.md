# JARVIS RobotAI - Asisten Pribadi Android ala Iron Man

Aplikasi Flutter + Groq AI (gratis) + Voice (Indonesia) + Popup Overlay + Kontrol HP via suara.

## Fitur v1
- Tap orb -> bicara Indonesia -> Jarvis menjawab via suara + teks
- Perintah lokal (offline, cepat):
  - "buka whatsapp / youtube / ig / tiktok / kamera / pengaturan ..." (buka aplikasi apapun)
  - "tutup aplikasi" (via Accessibility + finish task)
  - "kembali ke home"
  - "kunci layar / matikan layar / matikan hp" (via Device Admin)
  - "nyalakan/matikan senter"
  - "volume naik / turun"
- Selain itu -> dijawab Groq AI `llama-3.3-70b-versatile` gaya Jarvis Indonesia campur Inggris
- Popup RobotAI melayang di atas aplikasi lain (tombol overlay di AppBar)
- Simpan Groq API key di Settings (SharedPreferences)

## Jujur soal batasan Android (penting!)
1. **Nyalakan HP dari mati total = TIDAK BISA via aplikasi.** Itu butuh tombol power (hardware). Yang bisa: kunci layar, matikan layar, sleep, restart (root).
2. **Tutup aplikasi lain di Android 10+ dibatasi Google.** Solusi di app ini: AccessibilityService + finishAndRemoveTask + BACK/HOME. Aktifkan di Settings > Accessibility > Jarvis.
3. **Popup overlay butuh izin SYSTEM_ALERT_WINDOW.** Sudah diminta otomatis saat tap tombol overlay.
4. **Kunci layar butuh Device Admin.** Akan diminta sekali, aktifkan.

## Struktur
```
lib/
  main.dart
  core/groq_service.dart       -> otak Groq
  core/voice_service.dart      -> STT id-ID + TTS id-ID
  core/command_parser.dart     -> "buka...", "kunci layar", ...
  core/app_controller.dart     -> MethodChannel jarvis/control
  core/overlay_service.dart
  ui/home_screen.dart
  ui/jarvis_orb.dart
  overlay/overlay_widget.dart  -> UI popup melayang
android/.../MainActivity.kt    -> openApp, closeApp, lock, flash, volume
```

## API Key Groq Gratis
1. Buka https://console.groq.com -> Login -> API Keys -> Create
2. Copy `gsk_...` -> buka app -> ikon Settings -> paste -> Save
