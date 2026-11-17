#!/data/data/com.termux/files/usr/bin/bash
set -e
DIR="assets/pieces"
mkdir -p "$DIR"
BASE="https://raw.githubusercontent.com/lichess-org/lila/master/public/piece/cburnett"
for p in wK wQ wR wB wN wP bK bQ bR bB bN bP; do
  if [ ! -f "$DIR/$p.svg" ]; then
    echo "[get ] $p.svg"
    wget -q -O "$DIR/$p.svg" "$BASE/$p.svg"
  fi
done
echo "Selesai. Isi assets/pieces:"
ls -1 "$DIR"
