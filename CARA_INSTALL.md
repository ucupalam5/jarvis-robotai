# CARA INSTALL & BUILD APK - JARVIS RobotAI

Pilih 1 cara termudah buat kamu:

## Cara A: Build di PC (Recommended, 15 menit)
1. Install Flutter SDK: https://docs.flutter.dev/get-started/install
2. Install Android Studio + Android SDK + accept licenses:
   ```
   flutter doctor
   flutter doctor --android-licenses
   ```
3. Copy folder `jarvis_robotai` ini ke PC kamu.
4. Di dalam folder:
   ```
   flutter pub get
   flutter run            # test di HP via USB debugging
   flutter build apk --release
   ```
5. APK jadi di `build/app/outputs/flutter-apk/app-release.apk` -> kirim ke HP -> install.
6. Di HP: izinkan Microphone + Overlay + Accessibility + Device Admin saat diminta app.

## Cara B: Langsung di HP Android (tanpa PC, pakai Termux + Flutter manual - agak berat)
- Kurang disarankan karena Flutter build butuh 4GB+ RAM. Lebih baik pinjam PC / pakai Cara C.

## Cara C: Saya bantu convert ke template online (opsional)
- Upload folder ini ke GitHub, connect ke https://appetize.io / Codemagic untuk build APK otomatis di cloud gratis.

## Setelah install di HP
1. Buka JARVIS RobotAI -> ikon Settings (kanan atas) -> paste Groq API key `gsk_...` -> Save.
   - Daftar gratis: https://console.groq.com
2. Tap orb biru -> izinkan microphone -> coba: "buka whatsapp", "buka youtube".
3. Coba "kunci layar" -> aktifkan Device Admin saat diminta.
4. Aktifkan tutup-app sempurna: Settings HP -> Accessibility -> Jarvis -> ON.
5. Tap ikon overlay (atas) -> izinkan "Display over other apps" -> popup Jarvis melayang, bisa digeser.

## Contoh perintah suara
- "Jarvis buka WhatsApp"
- "Bukain YouTube dong"
- "Tutup aplikasi"
- "Kunci layar"
- "Nyalakan senter" / "Matikan senter"
- "Volume naik"
- "Siapa presiden Indonesia?" (dijawab Groq AI)
- "Jelaskan AI singkat aja" (dijawab + diucapkan)

## Troubleshooting
- STT tidak dengar: cek izin mic + bahasa STT id-ID + coba di ruangan sepi.
- Groq 401: API key salah / expired -> buat baru.
- Groq 429: kuota gratis habis -> tunggu 1 menit / ganti key.
- Overlay tidak muncul: Settings -> Apps -> Jarvis -> Display over other apps -> Allow.
- Gagal kunci layar: aktifkan Device Admin (akan diminta otomatis).
