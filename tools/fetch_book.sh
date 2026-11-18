#!/data/data/com.termux/files/usr/bin/bash
set -e
mkdir -p assets/book
if [ ! -f assets/book/openings.tsv ]; then
  echo "[get ] openings.tsv (~3MB)"
  wget -q --show-progress -O assets/book/openings.tsv \
    "https://raw.githubusercontent.com/lichess-org/chess-openings/master/dist/openings.tsv"
else
  echo "[skip] openings.tsv sudah ada"
fi
echo "Selesai. Cek:"
ls -lh assets/book/openings.tsv
