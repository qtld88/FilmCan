#!/usr/bin/env bash
# Fake camera cards and backup SSDs as sparse disk images, for testing FilmCan
# without hardware. Images live in $FILMCAN_FAKE_DIR (default ~/FilmCanFakeMedia).
#
#   fake_volumes.sh create   build every image (once) and mount them
#   fake_volumes.sh mount    mount every image
#   fake_volumes.sh unmount  eject every image
#   fake_volumes.sh reset    eject and delete every image, then create again
#   fake_volumes.sh wipe     eject and delete every image
set -euo pipefail

ROOT="${FILMCAN_FAKE_DIR:-$HOME/FilmCanFakeMedia}"
BIG_CLIP_MB="${BIG_CLIP_MB:-3000}"

# image file | volume name | filesystem | max size
VOLUMES=(
  "card_sony|Untitled|ExFAT|5g"
  "card_canon|Untitled|ExFAT|1g"
  "card_arri|A001R2EC|ExFAT|1g"
  "card_red|RED_MAG|ExFAT|1g"
  "card_gopro|GOPRO|MS-DOS FAT32|1g"
  "card_dji|DJI_DRONE|ExFAT|1g"
  "card_sound|ZOOM_F8|ExFAT|1g"
  "stick_docs|DOCS_STICK|ExFAT|1g"
  "ssd_a|SHUTTLE_A|APFS|20g"
  "ssd_b|SHUTTLE_B|APFS|20g"
  "ssd_spare|SPARE_EXFAT|ExFAT|20g"
)

need() { command -v "$1" >/dev/null || { echo "missing: $1 (brew install $1)"; exit 1; }; }

image_path() { echo "$ROOT/$1.sparseimage"; }

attach() {
  hdiutil attach "$(image_path "$1")" | awk -F'\t' 'NF>=3 && $3 ~ /^\/Volumes\// {print $3}' | tail -1
}

is_attached() {
  hdiutil info | grep -qF "$(image_path "$1")"
}

detach() {
  local img dev
  img="$(image_path "$1")"
  dev="$(hdiutil info | awk -v img="$img" '
    $0 ~ "image-path" && index($0, img) {found=1; next}
    found && /^\/dev\/disk[0-9]+[ \t]/ {print $1; exit}')"
  [ -n "$dev" ] && hdiutil detach -quiet "$dev" -force || true
}

video() {   # path seconds
  ffmpeg -loglevel error -y -f lavfi -i "testsrc2=size=1280x720:rate=25:duration=$2" \
    -f lavfi -i "sine=frequency=440:duration=$2" -shortest \
    -c:v libx264 -pix_fmt yuv420p -c:a aac "$1"
}

wav() {     # path seconds frequency
  ffmpeg -loglevel error -y -f lavfi -i "sine=frequency=$3:duration=$2" -ar 48000 -c:a pcm_s24le "$1"
}

junk() {    # path megabytes
  dd if=/dev/urandom of="$1" bs=1m count="$2" status=none
}

populate() {   # image mountpoint
  local m="$2"
  case "$1" in
    card_sony)
      mkdir -p "$m/PRIVATE/M4ROOT/CLIP" "$m/PRIVATE/M4ROOT/THMBNL"
      for i in 1 2 3 4; do
        video "$m/PRIVATE/M4ROOT/CLIP/C000$i.MP4" $((3 + i))
        echo "<NonRealTimeMeta clip=\"C000$i\"/>" > "$m/PRIVATE/M4ROOT/CLIP/C000${i}M01.XML"
      done
      echo "Big clip (${BIG_CLIP_MB} MB, gives time to press Stop)…"
      junk "$m/PRIVATE/M4ROOT/CLIP/C0005.MP4" "$BIG_CLIP_MB" ;;
    card_canon)
      mkdir -p "$m/DCIM/100CANON"
      for i in 1 2 3; do video "$m/DCIM/100CANON/MVI_000$i.MOV" 4; done ;;
    card_arri)
      mkdir -p "$m/A001R2EC"
      for i in 1 2 3; do junk "$m/A001R2EC/A001C00${i}_261105_R2EC.mxf" 20; done ;;
    card_red)
      local clip="$m/A002_1105XY.RDM/A002_C001_1105AB.RDC"
      mkdir -p "$clip"
      junk "$clip/A002_C001_1105AB_001.R3D" 30
      junk "$clip/A002_C001_1105AB_002.R3D" 30 ;;
    card_gopro)
      mkdir -p "$m/DCIM/100GOPRO"
      video "$m/DCIM/100GOPRO/GX010001.MP4" 5
      video "$m/DCIM/100GOPRO/GX010002.MP4" 5 ;;
    card_dji)
      mkdir -p "$m/DCIM/DJI_001"
      video "$m/DCIM/DJI_001/DJI_0001.MP4" 6 ;;
    card_sound)
      mkdir -p "$m/FOLDER01"
      wav "$m/FOLDER01/T001.WAV" 20 440
      wav "$m/FOLDER01/T002.WAV" 20 660 ;;
    stick_docs)
      mkdir -p "$m/Documents"
      echo "Call sheet day 1" > "$m/Documents/callsheet.txt"
      echo "Budget" > "$m/Documents/budget.csv" ;;
  esac
}

create() {
  need ffmpeg
  mkdir -p "$ROOT"
  for entry in "${VOLUMES[@]}"; do
    IFS='|' read -r img name fs size <<<"$entry"
    if [ -f "$(image_path "$img")" ]; then
      echo "exists: $img"
      continue
    fi
    echo "creating $img ($name, $fs)"
    hdiutil create -quiet -type SPARSE -size "$size" -fs "$fs" -volname "$name" "$ROOT/$img"
    local m
    m="$(attach "$img")"
    [ -n "$m" ] || { echo "could not mount $img"; exit 1; }
    populate "$img" "$m"
  done
  mount_all
}

mount_all() {
  for entry in "${VOLUMES[@]}"; do
    IFS='|' read -r img _ <<<"$entry"
    [ -f "$(image_path "$img")" ] || continue
    is_attached "$img" || attach "$img" >/dev/null
  done
  echo "Mounted:"
  hdiutil info | awk -v root="$ROOT" '
    $0 ~ "image-path" && index($0, root) {split($0, a, "/"); img=a[length(a)]; next}
    img && /\/Volumes\// {sub(/.*\t/, ""); print "  " img " → " $0; img=""}'
}

unmount_all() {
  for entry in "${VOLUMES[@]}"; do
    IFS='|' read -r img _ <<<"$entry"
    detach "$img"
  done
  echo "All fake volumes ejected."
}

wipe() {
  unmount_all
  for entry in "${VOLUMES[@]}"; do
    IFS='|' read -r img _ <<<"$entry"
    rm -f "$(image_path "$img")"
  done
  echo "Images deleted from $ROOT."
}

case "${1:-}" in
  create)  create ;;
  mount)   mount_all ;;
  unmount) unmount_all ;;
  reset)   wipe; create ;;
  wipe)    wipe ;;
  *) sed -n '2,10p' "$0"; exit 1 ;;
esac
