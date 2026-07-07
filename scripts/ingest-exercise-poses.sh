#!/bin/bash
# Ingest exercise pose photos from free-exercise-db (#929).
#
# Source: github.com/yuhonas/free-exercise-db — Unlicense (public domain).
# Every catalog entry's imageUrl already points at this dataset, so the
# asset directory name comes straight from the catalog (no name matching).
# Each exercise has exactly two start/end pose JPGs (0.jpg, 1.jpg); we
# recompress to 400px HEIC (~9KB/frame at q45) → ~20MB for the full set,
# shipped in-bundle as a folder reference. No network at runtime.
#
# Run: bash scripts/ingest-exercise-poses.sh
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="Drift/ExercisePoses"
TMP="/tmp/fed-poses"
mkdir -p "$OUT" "$TMP"

# Asset dirs derived from the catalog's imageUrls (unique, sorted).
python3 - <<'EOF' > /tmp/fed-dirs.txt
import json, re
ex = json.load(open('DriftCore/Sources/DriftCore/Resources/exercises.json'))
dirs = set()
for e in ex:
    m = re.search(r'free-exercise-db/main/exercises/([^/]+)/', e.get('imageUrl') or '')
    if m: dirs.add(m.group(1))
print("\n".join(sorted(dirs)))
EOF
TOTAL=$(wc -l < /tmp/fed-dirs.txt | tr -d ' ')
echo "asset dirs: $TOTAL"

# 1. Download both poses per dir (parallel, resumable — skips existing).
download() {
  local dir="$1" idx="$2"
  local jpg="$TMP/${dir}-${idx}.jpg"
  [ -s "$jpg" ] && return 0
  curl -sf "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/${dir}/${idx}.jpg" -o "$jpg" || rm -f "$jpg"
}
export -f download
export TMP
awk '{print $0" 0\n"$0" 1"}' /tmp/fed-dirs.txt \
  | xargs -P 12 -n 2 bash -c 'download "$0" "$1"'
echo "downloaded: $(ls "$TMP" | grep -c jpg || true) jpgs"

# 2. Recompress → 400px HEIC (skip existing for resumability).
converted=0
while read -r dir; do
  for idx in 0 1; do
    src="$TMP/${dir}-${idx}.jpg"
    dst="$OUT/${dir}-${idx}.heic"
    [ -s "$src" ] || continue
    [ -s "$dst" ] && continue
    sips -s format heic -s formatOptions 45 -Z 400 "$src" --out "$dst" >/dev/null 2>&1 && converted=$((converted+1))
  done
done < /tmp/fed-dirs.txt
echo "converted this run: $converted"
echo "pack: $(ls "$OUT" | wc -l | tr -d ' ') files, $(du -sh "$OUT" | cut -f1)"
