#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXT="$ROOT/external"
mkdir -p "$EXT"

fetch_tar() {
  local name="$1" url="$2" dest="$3"
  if [ -d "$dest" ] && [ -n "$(ls -A "$dest" 2>/dev/null)" ]; then
    echo "[skip] $name sudah ada"
    return
  fi
  echo "[get ] $name"
  local tmp="$EXT/.$name.tar"
  wget -q --show-progress -O "$tmp" "$url"
  mkdir -p "$dest"
  tar -xf "$tmp" -C "$dest" --strip-components=1
  rm -f "$tmp"
  echo "[ok  ] $name"
}

fetch_tar "sf16.1" \
  "https://github.com/official-stockfish/Stockfish/archive/refs/tags/sf_16.1.tar.gz" \
  "$EXT/sf16"

fetch_tar "sf11" \
  "https://github.com/official-stockfish/Stockfish/archive/refs/tags/sf_11.tar.gz" \
  "$EXT/sf11"

# NNUE untuk SF 16.1: dua net (besar + kecil), sesuai yang di-embed.
NNUE_DIR="$EXT/nnue"
mkdir -p "$NNUE_DIR"
for f in nn-b1a57edbea57.nnue nn-baff1ede1f90.nnue; do
  if [ ! -f "$NNUE_DIR/$f" ]; then
    echo "[get ] $f"
    wget -q --show-progress -O "$NNUE_DIR/$f" \
      "https://tests.stockfishchess.org/api/nn/$f"
  else
    echo "[skip] $f"
  fi
done

echo "Selesai. NNUE:"
ls -1 "$NNUE_DIR"
