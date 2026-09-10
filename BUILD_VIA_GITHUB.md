# BUILD APK TANPA PC — via GitHub Actions (100% dari HP)

Jawaban singkat: **YA, BISA.** GitHub kasih mesin Ubuntu gratis untuk build Flutter APK kamu. Kamu cukup upload file dari HP via browser Chrome.

## Cara 10 menit (hanya HP + browser)

### 1. Siapkan file di HP
- Download / copy folder `jarvis_robotai/` dari saya ke HP kamu (atau via Termux `git clone` bila sudah di GitHub).
- Pastikan ada file `.github/workflows/build-apk.yml` (sudah saya buatkan).

### 2. Buat repo GitHub dari HP
1. Buka Chrome HP -> github.com -> login -> New repository
   - Nama: `jarvis-robotai`, Public, centang Add README.
2. Tap Add file > Upload files > pilih **semua isi** folder `jarvis_robotai/` (lib/, android/, pubspec.yaml, .github/).
   - Trik HP: zip dulu via file manager (ZArchiver), upload zip? GitHub web HP tidak bisa unzip. Lebih gampang:
   - Install app **Spck Editor** / **Acode** dari Play Store -> open folder -> Git -> push ke GitHub. Atau:
   - Di Termux: `pkg install git gh`, `gh auth login`, `git init`, `git add .`, `git commit`, `git push`.
3. Setelah push, buka tab **Actions** di repo -> workflow `Build Jarvis APK` jalan otomatis (3-8 menit).

### 3. Download APK
- Actions -> klik run terbaru yang hijau -> scroll **Artifacts** -> download `jarvis-app-release` (zip berisi `app-release.apk`).
- Pindah ke HP -> install -> izinkan Unknown apps.

### 4. Setelah install
1. Install app **Shizuku** dari Play Store.
2. Shizuku > Pairing > aktifkan Opsi Pengembang > Wireless Debugging > Pair dengan kode (TANPA PC, pairing lokal di HP yang sama, Android 11+).
3. Shizuku > Start -> Authorized apps -> izinkan `com.jarvis.robotai`.
4. Buka Jarvis -> chip Shizuku harus hijau `OK`. Bila `BELUM_IZIN`, tap `Izin Shizuku`.
5. Settings Jarvis: isi Groq key + PIN (opsional).
6. Coba: "nyalakan layar", "buka youtube", "ketik halo", "tap kirim".

## Troubleshooting GitHub Actions
- `flutter.sdk not set` / Gradle error: pastikan push **isi folder**, bukan folder zip. Struktur repo harus langsung ada `pubspec.yaml` di root.
- Build 15+ menit / fail di `flutter build apk`: cek log Actions. Umumnya Java 17 vs 21 mismatch — workflow saya sudah pakai Java 17 + Flutter 3.24 yang stabil.
- Artifact kosong: pastikan build sukses (centang hijau). APK ada di `build/app/outputs/flutter-apk/app-release.apk`.
- Update app: edit file -> push lagi -> APK baru otomatis jadi.

## Batas jujur Shizuku
- Shizuku = izin ADB, BUKAN root. Bisa `input tap/text/keyevent`, `am start`, `cmd`. **Tidak bisa**: nyalakan HP mati total, bobol PIN di Samsung/Xiaomi baru (tetap diblokir sistem), kirim WA 100% background (WA tidak ada API).
- Alur WA otomatis maksimal: `kirim wa ke 0812 halo` -> buka chat -> `ketik ...` -> `tap kirim`. Kadang koordinat tombol kirim beda per HP — sesuaikan x y di `ShizukuHelper.tap()` / perintah `shizuku input tap x y`.
