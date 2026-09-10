#!/data/data/com.termux/files/usr/bin/bash
# Push Jarvis ke GitHub 100% dari HP via Termux - tanpa PC
# Jalankan: bash push_to_github.sh
set -e
echo "=== JARVIS GitHub Push, Sir ==="

# 1. Install git + gh bila belum ada
if ! command -v git >/dev/null; then pkg update -y && pkg install -y git; fi
if ! command -v gh >/dev/null; then pkg install -y gh; fi

# 2. Folder kerja = folder script ini
cd "$(dirname "$0")"

# 3. Init repo bila belum ada
if [ ! -d .git ]; then
  git init -b main
fi

# 4. Login GitHub (hanya sekali, token tersimpan di HP)
if ! gh auth status >/dev/null 2>&1; then
  echo ""
  echo "Login GitHub dulu ya Sir (hanya sekali):"
  echo "Pilih: GitHub.com > Login with web browser > copy kode 8 huruf."
  gh auth login
fi

# 5. Buat repo bila belum ada remote
if ! git remote get-url origin >/dev/null 2>&1; then
  echo ""
  read -p "Nama repo [jarvis-robotai]: " REPONAME
  REPONAME=${REPONAME:-jarvis-robotai}
  gh repo create "$REPONAME" --public --source=. --push || {
    echo "Repo mungkin sudah ada. Sambungkan manual:"
    echo "  git remote add origin https://github.com/USERNAME/$REPONAME.git"
    exit 1
  }
fi

# 6. Push
git add -A
git commit -m "Jarvis RobotAI + Shizuku + workflow APK" || echo "(tidak ada perubahan baru)"
git branch -M main
git push -u origin main

echo ""
echo "=== SUKSES, Sir ==="
echo "Buka di Chrome HP: github.com/USERNAME/jarvis-robotai > tab Actions"
echo "Tunggu 3-8 menit sampai hijau > download Artifacts > jarvis-app-release > app-release.apk"
