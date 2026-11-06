#!/bin/bash
# FilmCan promo screenshots, driven by the DEBUG demo mode (see docs/promo/asset-list.md, sections 5-6).
#
#   scripts/promo_screenshots.sh setup           build the Debug app if missing, create/mount the fake volumes, reset the fake home
#   scripts/promo_screenshots.sh shot <name>...  capture named images (e.g. 03 05 21), launching the app as needed
#   scripts/promo_screenshots.sh all             setup + every image + derived images (hero, og-image)
#   scripts/promo_screenshots.sh derive          rebuild screenshot-main.png x2 and og-image.png from 03
#   scripts/promo_screenshots.sh cleanup         quit the app, unmount + delete the fake images, remove the promo prefs
#
# Safety: the app only ever runs with CFFIXED_USER_HOME pointing at the fake home under $PROMO_WORK.
# The script refuses to run if that path is, contains, or sits inside the real home's Library.
# The fake volumes (A003R1KD, DJI_RONIN, ZOOM_F6, CK_backup_01/02) are sparse disk images made by this
# script; any other mounted volume is never touched. If a real volume already has one of those names,
# the script stops.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="${PROMO_WORK:-${TMPDIR:-/tmp}/filmcan-promo}"
WORK="${WORK%/}"
FAKE_HOME="$WORK/fakehome"
VOL="$WORK/vol"
SHOTS="$WORK/shots"
FIXTURES="$ROOT/scripts/promo_fixtures"
OUT="$ROOT/assets/promo"
SRC_APP="${PROMO_APP:-$ROOT/FilmCan/build/promo/Build/Products/Debug/FilmCan.app}"
# The app runs as a COPY with its own bundle id, so its preferences (domain below) never touch the real
# com.filmcan.app domain (real ntfy URL, last-used movie, window frames...).
APP="$WORK/promo-app/FilmCan.app"
BUNDLE_ID=com.filmcan.app.promo
CONFIG_ID=50C0C643-DAA3-4182-BCAF-50CFF5D8BE04
SPEED=500
TOTAL_GB=14.99      # A003R1KD + DJI_RONIN + ZOOM_F6 (main window)
QC_TOTAL_GB=14.69   # A003R1KD + DJI_RONIN only (Quick Copy)
SEARCH_TERM=A003C00

guard_home() {
  local real fake
  real="$(dscl . -read "/Users/$(id -un)" NFSHomeDirectory | awk '{print $2}')"
  mkdir -p "$FAKE_HOME"
  fake="$(cd "$FAKE_HOME" && pwd -P)"
  real="$(cd "$real" && pwd -P)"
  case "$fake" in
    "$real"|"$real/Library"*|"$real/Library") echo "REFUSED: fake home $fake is the real home or inside its Library" >&2; exit 1 ;;
  esac
  case "$real" in
    "$fake"|"$fake"/*) echo "REFUSED: fake home $fake contains the real home" >&2; exit 1 ;;
  esac
  [ "$fake" != "/" ] && [ -n "$fake" ] || { echo "REFUSED: bad fake home" >&2; exit 1; }
  case "$(basename "$fake")" in fakehome) ;; *) echo "REFUSED: fake home must be named 'fakehome'" >&2; exit 1 ;; esac
}

# ---- volumes -------------------------------------------------------------------------------------
vol_mounted() { [ -d "/Volumes/$1" ]; }

mkvol() { # name size
  local name="$1" size="$2" img="$VOL/$1.sparseimage"
  if vol_mounted "$name"; then
    hdiutil info | grep -F "$img" >/dev/null || { echo "REFUSED: a volume named $name is mounted and is not our fake image" >&2; exit 1; }
    return
  fi
  [ -f "$img" ] || hdiutil create -quiet -type SPARSE -fs APFS -volname "$name" -size "$size" "$img"
  hdiutil attach -quiet "$img"
}

fill() { # dir prefix count bytes
  local dir="$1" i
  mkdir -p "$dir"
  find "$dir" -type f ! -name '.*' -delete
  for i in $(seq 1 "$3"); do
    case "$2" in
      arri) truncate -s "$4" "$dir/A003C$(printf %03d "$i")_261104_R1KD.mov" ;;
      dji)  truncate -s "$4" "$dir/DJI_$(printf %04d "$i").MP4" ;;
      wav)  truncate -s "$4" "$dir/F8_$(printf %03d "$i").WAV" ;;
    esac
  done
}

setup_volumes() {
  mkdir -p "$VOL" "$SHOTS"
  mkvol A003R1KD 11g; mkvol DJI_RONIN 7g; mkvol ZOOM_F6 2g
  mkvol CK_backup_01 32g; mkvol CK_backup_02 32g
  # sparse placeholders: ~9.8 GB (11 clips), ~4.9 GB (13 clips), ~0.3 GB (10 WAVs) = 14.99 GB
  fill /Volumes/A003R1KD/A003R1KD arri 11 890000000
  fill /Volumes/DJI_RONIN/DCIM/100MEDIA dji 13 377000000
  fill /Volumes/ZOOM_F6/SOUND wav 10 30000000
  local v
  for v in CK_backup_01 CK_backup_02; do find "/Volumes/$v" -mindepth 1 -maxdepth 1 ! -name '.*' -exec rm -rf {} + ; done
}

reset_fake_home() {
  guard_home
  local d="$FAKE_HOME/Library/Application Support/FilmCan"
  mkdir -p "$d"
  cp "$FIXTURES"/configs.json "$FIXTURES"/presets.json "$FIXTURES"/history.json "$FIXTURES"/catalog.json "$d/"
}

# ---- app -----------------------------------------------------------------------------------------
build_app() {
  if [ ! -d "$SRC_APP" ]; then
    echo "building Debug app..."
    xcodebuild build -project "$ROOT/FilmCan/FilmCan.xcodeproj" -scheme FilmCan -configuration Debug \
      -destination platform=macOS -derivedDataPath "$ROOT/FilmCan/build/promo" -quiet
  fi
  # promo variant: other bundle id, no Finder Services entry, ad-hoc signature
  if [ ! -d "$APP" ] || [ "$SRC_APP/Contents/MacOS/FilmCan" -nt "$APP/Contents/MacOS/FilmCan" ]; then
    rm -rf "$WORK/promo-app"; mkdir -p "$WORK/promo-app"
    cp -R "$SRC_APP" "$APP"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Delete :NSServices" "$APP/Contents/Info.plist" 2>/dev/null || true
    codesign -d --entitlements "$WORK/ent.plist" --xml "$SRC_APP" 2>/dev/null || true
    codesign --force --deep -s - --entitlements "$WORK/ent.plist" "$APP" 2>&1 | tail -1
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$APP"
  fi
}

winid_tool() {
  local bin="$WORK/winid"
  if [ ! -x "$bin" ]; then
    cat > "$WORK/winid.swift" <<'SWIFT'
import CoreGraphics
import Foundation
let pid = Int(CommandLine.arguments[1])!
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerPID as String] as? Int) == pid {
  let b = w[kCGWindowBounds as String] as! [String: Any]
  if (b["Width"] as! Double) < 200 { continue }
  print(w[kCGWindowNumber as String]!, Int(b["Width"] as! Double), Int(b["Height"] as! Double), (w[kCGWindowName as String] as? String) ?? "-", w[kCGWindowIsOnscreen as String] ?? false)
}
SWIFT
    swiftc -O "$WORK/winid.swift" -o "$bin" 2>/dev/null
  fi
  echo "$bin"
}

app_pid() { pgrep -f "$APP/Contents/MacOS/FilmCan" | head -1 || true; }

quit_app() {
  pkill -f "$APP/Contents/MacOS/FilmCan" 2>/dev/null || true
  local i; for i in 1 2 3 4 5 6; do [ -z "$(app_pid)" ] && return; sleep 0.5; done
}

launch() { # [FILMCAN_DEMO_*=value ...]
  guard_home
  build_app
  quit_app
  defaults write "$BUNDLE_ID" didShowQuickTour -bool true
  defaults write "$BUNDLE_ID" donationPromptSuppressed -bool true
  CFFIXED_USER_HOME="$FAKE_HOME" defaults write "$BUNDLE_ID" lastUsedConfigurationId "$CONFIG_ID"
  CFFIXED_USER_HOME="$FAKE_HOME" defaults write "$BUNDLE_ID" quickCopy.lastPresetId \
    "$(python3 -I -c "import json,sys;print(json.load(open(sys.argv[1]))[0]['id'])" "$FAKE_HOME/Library/Application Support/FilmCan/presets.json")"
  CFFIXED_USER_HOME="$FAKE_HOME" defaults write "$BUNDLE_ID" quickCopy.lastDestinations -array /Volumes/CK_backup_01 /Volumes/CK_backup_02
  local envs=(--env "CFFIXED_USER_HOME=$FAKE_HOME") e
  for e in "$@"; do envs+=(--env "$e"); done
  open -n "${envs[@]}" "$APP"
  local i; for i in $(seq 1 30); do [ -n "$(app_pid)" ] && break; sleep 0.5; done
  sleep 5
}

# window id of the first window of the given size (default main window) ; prints id
window_id() { # width height
  "$(winid_tool)" "$(app_pid)" | awk -v w="$1" -v h="$2" '$2==w && $3==h {print $1; exit}'
}

front() {
  open -a "$APP" 2>/dev/null || true
  sleep 0.5
  osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $(app_pid)) to true" >/dev/null
  sleep 1
}

# the main window opens at the saved/default size; set the documented 1392x873 pt
fit_main() {
  osascript -e "tell application \"System Events\" to tell (first process whose unix id is $(app_pid)) to tell window 1 to set {position, size} to {{60, 40}, {1392, 873}}" >/dev/null 2>&1 || true
  sleep 1.5
}

capture() { # name width height
  [ "$2" = 1392 ] && fit_main
  local id; id="$(window_id "$2" "$3")"
  [ -n "$id" ] || { echo "no ${2}x${3} window for $1" >&2; "$(winid_tool)" "$(app_pid)" >&2; return 1; }
  front
  screencapture -o -x -l "$id" "$OUT/$1.png"
  echo "captured $1 ($(sips -g pixelWidth -g pixelHeight "$OUT/$1.png" | awk '/pixel/{printf $2"x"}'))"
}

demo_env() { # state progress [total_gb]
  echo "FILMCAN_DEMO_STATE=$1" "FILMCAN_DEMO_PROGRESS=$2" "FILMCAN_DEMO_SPEED_MBPS=$SPEED" "FILMCAN_DEMO_TOTAL_GB=${3:-$TOTAL_GB}"
}

main_demo() { # file state progress
  launch $(demo_env "$2" "$3")
  capture "$1" 1392 873
}

QC_ENV=("FILMCAN_DEMO_QUICKCOPY=/Volumes/A003R1KD,/Volumes/DJI_RONIN" "FILMCAN_DEMO_QUICKCOPY_DEST=/Volumes/CK_backup_01,/Volumes/CK_backup_02")
QC_W=900; QC_H=652

qc_demo() { # file state progress
  launch "${QC_ENV[@]}" $(demo_env "$2" "$3" "$QC_TOTAL_GB")
  capture "$1" $QC_W $QC_H
}

# UI navigation helpers (System Events). Needs Accessibility permission for the terminal running this.
menu_click() { # menu-bar item, item
  front
  osascript -e "tell application \"System Events\" to tell (first process whose unix id is $(app_pid)) to click menu item \"$2\" of menu 1 of menu bar item \"$1\" of menu bar 1" >/dev/null
  sleep 2
}

ui_click() { # AppleScript expression for the element, e.g. 'radio button "Destinations" of group 1 of window 1'
  osascript -e "tell application \"System Events\" to tell (first process whose unix id is $(app_pid)) to click $1" >/dev/null
  sleep 1.2
}

frontmost_is_app() {
  [ "$(osascript -e 'tell application "System Events" to get unix id of first process whose frontmost is true')" = "$(app_pid)" ]
}

# click at screen points (window position + offset); refuses to click if FilmCan is not frontmost
click_in_main() { # x y  (window-relative points)
  front
  frontmost_is_app || { echo "FilmCan not frontmost; skipping click" >&2; return 1; }
  local pos x y
  pos="$(osascript -e "tell application \"System Events\" to tell (first process whose unix id is $(app_pid)) to get position of window 1" | tr -d ' ')"
  x=$(( ${pos%%,*} + $1 )); y=$(( ${pos##*,} + $2 ))
  "$(clk_tool)" click "$x" "$y"
  sleep 1.2
}

scroll_main() { # dy
  frontmost_is_app || return 1
  "$(clk_tool)" scroll 500 500 "$1"
  sleep 1
}

clk_tool() {
  local bin="$WORK/clk"
  if [ ! -x "$bin" ]; then
    cat > "$WORK/clk.swift" <<'SWIFT'
import CoreGraphics
import Foundation
let a = CommandLine.arguments
let p = CGPoint(x: Double(a[2])!, y: Double(a[3])!)
CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(150000)
if a[1] == "click" {
  for t in [CGEventType.leftMouseDown, .leftMouseUp] {
    CGEvent(mouseEventSource: nil, mouseType: t, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(80000)
  }
} else {
  for _ in 0..<12 {
    CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(a[4])!, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
    usleep(40000)
  }
}
SWIFT
    swiftc -O "$WORK/clk.swift" -o "$bin" 2>/dev/null
  fi
  echo "$bin"
}

# per-image navigation lives here; filled in by the cases below
SET_W=560; SET_H=748
# Settings tab centres, window-relative points (window 560x748)
settings_tab() { # name x
  click_in_main "$2" 56
  capture "$1" $SET_W $SET_H
}
open_settings() {
  launch
  local i
  for i in 1 2 3; do
    menu_click FilmCan "Settings…" || true
    [ -n "$(window_id $SET_W $SET_H)" ] && break
    sleep 2
  done
  capture 10-settings-appearance $SET_W $SET_H
}
shot_10() { open_settings; }
shot_11() { open_settings >/dev/null; settings_tab 11-settings-notifications 178; }
shot_12() { open_settings >/dev/null; settings_tab 12-settings-push 246; }
shot_13() { open_settings >/dev/null; settings_tab 13-settings-history 302; }
shot_14() { open_settings >/dev/null; settings_tab 14-settings-drives 358; }
shot_15() { open_settings >/dev/null; settings_tab 15-settings-hotkeys 414; }

# Options tabs (main window at rest): window-relative points
options_tab() { # name x
  launch; fit_main; click_in_main "$2" 684
}
shot_06() { options_tab 06 166; capture 06-options-source 1392 873; }
shot_07() { options_tab 07 249; capture 07-options-destinations 1392 873; }
shot_08() { options_tab 08 327; scroll_main -300; capture 08-options-logs 1392 873; }

type_text() { frontmost_is_app && osascript -e "tell application \"System Events\" to keystroke \"$1\"" ; sleep 1; }

shot_17() {
  launch; fit_main
  menu_click Window "Catalog"
  click_in_main 1135 135
  type_text "$SEARCH_TERM"
  capture 17-catalog-pane 1392 873
}

shot_16() {
  launch; fit_main
  menu_click Window "Open Catalog in Window"
  front
  click_in_main 200 28
  type_text "$SEARCH_TERM"
  capture 16-catalog-search 760 592
}

shot() {
  case "$1" in
    01) launch; capture 01-backup-ready 1392 873 ;;
    02) main_demo 02-backup-copying-36 copying 0.36 ;;
    03) main_demo 03-backup-copying-60 copying 0.60 ;;
    04) main_demo 04-backup-verifying-77 verifying 0.77 ;;
    05) main_demo 05-backup-done done 1 ;;
    20) launch "${QC_ENV[@]}"; capture 20-quickcopy-setup $QC_W $QC_H ;;
    21) qc_demo 21-quickcopy-copying-21 copying 0.21 ;;
    22) qc_demo 22-quickcopy-copying-48 copying 0.48 ;;
    23) qc_demo 23-quickcopy-verifying-88 verifying 0.88 ;;
    24) qc_demo 24-quickcopy-done done 1 ;;
    *) if declare -F "shot_$1" >/dev/null; then "shot_$1"; else echo "unknown shot $1" >&2; return 1; fi ;;
  esac
}

derive() {
  python3 -I - "$ROOT" <<'PY'
import sys, os, shutil
from PIL import Image, ImageDraw, ImageFont, ImageFilter
root = sys.argv[1]; os.chdir(root)
W, H = 1200, 630
bg = Image.new('RGBA', (W, H), (27, 27, 27, 255)); d = ImageDraw.Draw(bg)
F = lambda s, i: ImageFont.truetype('/System/Library/Fonts/Avenir Next.ttc', s, index=i)
yellow = (255, 201, 0); white = (244, 242, 238); f = F(58, 8)
d.text((60, 42), "Backup camera cards.", font=f, fill=white)
d.text((60, 108), "Verified.", font=f, fill=yellow)
d.text((60 + d.textlength("Verified. ", font=f), 108), "To every drive at once.", font=f, fill=white)
ic = Image.open('assets/icon.png').convert('RGBA').resize((64, 64), Image.LANCZOS)
shot = Image.open('assets/promo/03-backup-copying-60.png').convert('RGBA')
sw = 940; sh = int(shot.height * sw / shot.width); shot = shot.resize((sw, sh), Image.LANCZOS)
x = (W - sw) // 2; y = 215
lay = Image.new('RGBA', (W, H), (0, 0, 0, 0))
ImageDraw.Draw(lay).rounded_rectangle((x, y + 18, x + sw, y + sh + 18), radius=22, fill=(0, 0, 0, 170))
bg = Image.alpha_composite(bg, lay.filter(ImageFilter.GaussianBlur(26)))
b = Image.new('RGBA', (W, H), (0, 0, 0, 0))
ImageDraw.Draw(b).rounded_rectangle((x - 1, y - 1, x + sw, y + sh), radius=18, outline=(244, 242, 238, 80), width=2)
bg.alpha_composite(shot, (x, y)); bg = Image.alpha_composite(bg, b); bg.alpha_composite(ic, (W - 124, 40))
bg.convert('RGB').save('website/assets/og-image.png', optimize=True)
for dst in ('website/assets/screenshot-main.png', 'assets/screenshot-main.png'):
    shutil.copy('assets/promo/03-backup-copying-60.png', dst)
print('derived screenshot-main x2 + og-image')
PY
}

cleanup() {
  guard_home
  quit_app
  defaults delete com.filmcan.app.promo 2>/dev/null || true
  local v
  for v in A003R1KD DJI_RONIN ZOOM_F6 CK_backup_01 CK_backup_02; do
    if [ -f "$VOL/$v.sparseimage" ] && hdiutil info | grep -F "$VOL/$v.sparseimage" >/dev/null; then
      hdiutil detach -quiet "/Volumes/$v" || hdiutil detach -force -quiet "/Volumes/$v" || true
    fi
    rm -f "$VOL/$v.sparseimage"
  done
  echo "cleanup done (fake home kept at $FAKE_HOME; delete it by hand if unwanted)"
}

cmd="${1:-}"; shift || true
case "$cmd" in
  setup)   guard_home; build_app; setup_volumes; reset_fake_home; defaults delete "$BUNDLE_ID" 2>/dev/null || true ;;
  shot)    guard_home; for n in "$@"; do shot "$n"; done ;;
  all)     guard_home; build_app; setup_volumes; reset_fake_home; defaults delete "$BUNDLE_ID" 2>/dev/null || true
           for n in 01 02 03 04 05 06 07 08 10 11 12 13 14 15 16 17 20 21 22 23 24; do shot "$n"; done
           derive; quit_app ;;
  menu)    guard_home; menu_click "$1" "$2" ;;
  wins)    "$(winid_tool)" "$(app_pid)" ;;
  snap)    guard_home; capture "$1" "${2:-1392}" "${3:-873}" ;;
  derive)  derive ;;
  cleanup) cleanup ;;
  *) sed -n 2,9p "$0"; exit 1 ;;
esac
