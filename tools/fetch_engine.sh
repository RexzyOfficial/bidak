#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXT="$ROOT/external"
mkdir -p "$EXT"

fetch_tar() {
  local name="$1" url="$2" dest="$3"
  if [ -d "$dest" ] && [ -n "$(ls -A "$dest" 2>/dev/null)" ]; then
    echo "[skip] $name sudah ada di $dest"
    return
  fi
  echo "[get ] $name"
  local tmp="$EXT/.$name.tar"
  wget -q --show-progress -O "$tmp" "$url"
  mkdir -p "$dest"
  tar -xf "$tmp" -C "$dest" --strip-components=1
  rm -f "$tmp"
  echo "[ok  ] $name -> $dest"
}

# Stockfish 16.1 (arm64, NNUE penuh)
fetch_tar "sf16.1" \
  "https://github.com/official-stockfish/Stockfish/archive/refs/tags/sf_16.1.tar.gz" \
  "$EXT/sf16"

# Stockfish 11 (armeabi-v7a, klasik 32-bit)
fetch_tar "sf11" \
  "https://github.com/official-stockfish/Stockfish/archive/refs/tags/sf_11.tar.gz" \
  "$EXT/sf11"

# NNUE penuh untuk SF 16.1.
# Nama file diverifikasi dari header respons; fallback ke nama yang dikenal.
NNUE_DIR="$EXT/nnue"
mkdir -p "$NNUE_DIR"
if [ -z "$(ls -A "$NNUE_DIR" 2>/dev/null)" ]; then
  echo "[get ] nnue penuh"
  # Coba dua kandidat nama resmi SF 16.1.
  for f in nn-5af11540bbfe.nnue nn-1111cefa1111.nnue; do
    url="https://tests.stockfishchess.org/api/nn/$f"
    if wget -q --spider "$url"; then
      wget -q --show-progress -O "$NNUE_DIR/$f" "$url"
      echo "[ok  ] nnue -> $NNUE_DIR/$f"
      break
    fi
  done
  if [ -z "$(ls -A "$NNUE_DIR" 2>/dev/null)" ]; then
    echo "[ERR ] tidak ada kandidat NNUE yang bisa diunduh. Cek manual:"
    echo "       https://github.com/official-stockfish/networks"
    exit 1
  fi
fi

echo
echo "Selesai. Isi external/:"
ls -1 "$EXT"
echo "NNUE:"
ls -1 "$NNUE_DIR" || true
