#!/data/data/com.termux/files/usr/bin/bash
set -e
mkdir -p assets/book
OUT=assets/book/openings.tsv

if [ -s "$OUT" ] && [ "$(wc -l < "$OUT")" -gt 100 ]; then
  echo "[skip] openings.tsv sudah ada ($(wc -l < "$OUT") baris)"
  exit 0
fi
rm -f "$OUT"

BASE="https://raw.githubusercontent.com/lichess-org/chess-openings/master"
TMP=$(mktemp)
first=1
for f in a b c d e; do
  echo "[get ] $f.tsv"
  if ! wget -q -O "$TMP" "$BASE/$f.tsv"; then
    echo "[gagal] $f.tsv - cek koneksi / URL"
    rm -f "$TMP" "$OUT"
    exit 1
  fi
  if [ "$first" = 1 ]; then
    cat "$TMP" > "$OUT"
    first=0
  else
    tail -n +2 "$TMP" >> "$OUT"
  fi
done
rm -f "$TMP"
echo "Selesai: $(wc -l < "$OUT") baris"
ls -lh "$OUT"
