#!/bin/bash
set -euo pipefail
trap 'echo "error: command failed: ${BASH_COMMAND}" >&2' ERR

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_DIR="${ROOT_DIR}/build/DerivedData"
cd "$ROOT_DIR"

REGEN_PROJECT="${REGEN_PROJECT:-0}"
if [ "$REGEN_PROJECT" = "1" ]; then
  xcodegen generate
fi

# Code-signing identity.
#
# Ad-hoc signing ("-") emits a cdhash-based designated requirement, new on every build.
# Signing with a certificate emits `certificate root = H"<cert sha1>"` instead, identical
# across builds — verified 2026-08-07 by signing two binaries with different cdhashes and
# diffing `codesign -d -r-`.
#
# What this does NOT do: it does not fix the saved ntfy token disappearing on update, and
# it does not get past Gatekeeper (the DMG is still un-notarized, still right-click ->
# Open). The token is guarded by the keychain *partition list*, which macOS pins to
# `cdhash:` unless the signing chain is Apple-anchored with a team OU — a self-signed root
# is not, so the partition stays cdhash-keyed and a new build is still refused. Measured,
# not assumed: see docs/release.md. Do not re-derive that fix from the requirement string.
#
# Resolved by name so no machine-specific hash lives in the repo. A checkout without the
# certificate falls back to ad-hoc and still builds. Set FILMCAN_SIGN_IDENTITY to force a
# specific identity, or to "-" to force ad-hoc.
SIGN_IDENTITY_NAME="${FILMCAN_SIGN_IDENTITY_NAME:-FilmCan Release}"
if [ -n "${FILMCAN_SIGN_IDENTITY:-}" ]; then
  SIGN_IDENTITY="$FILMCAN_SIGN_IDENTITY"
else
  # `find-identity -v` hides it: a self-signed root reports CSSMERR_TP_NOT_TRUSTED and so
  # is never "valid". codesign accepts it anyway, so match against the unfiltered list.
  SIGN_IDENTITY="$(security find-identity -p codesigning 2>/dev/null \
    | awk -v n="\"${SIGN_IDENTITY_NAME}\"" '$0 ~ n {print $2; exit}')"
  SIGN_IDENTITY="${SIGN_IDENTITY:--}"
fi

if [ "$SIGN_IDENTITY" = "-" ]; then
  echo "warning: no '${SIGN_IDENTITY_NAME}' code-signing certificate found; signing ad-hoc." >&2
  echo "warning: the designated requirement will be cdhash-based and change every build." >&2
  echo "warning: See docs/release.md." >&2
else
  echo "Signing identity: ${SIGN_IDENTITY_NAME} (${SIGN_IDENTITY})"
fi

build_for_arch() {
  local arch="$1"
  local dd_path="${DERIVED_DATA_DIR}-${arch}"
  local log_path="${DERIVED_DATA_DIR}/xcodebuild-${arch}.log"
  mkdir -p "$(dirname "$log_path")"
  if ! xcodebuild -project FilmCan.xcodeproj -scheme FilmCan -configuration Release \
    -derivedDataPath "$dd_path" ARCHS="$arch" ONLY_ACTIVE_ARCH=NO build \
    >"$log_path" 2>&1; then
    echo "error: xcodebuild failed for ${arch}. See ${log_path}" >&2
    tail -n 200 "$log_path" >&2 || true
    exit 1
  fi
  echo "$dd_path"
}

DERIVED_ARM64="$(build_for_arch arm64)"
DERIVED_X86_64="$(build_for_arch x86_64)"

TARGET_BUILD_DIR="$(
  xcodebuild -project FilmCan.xcodeproj -scheme FilmCan -configuration Release \
    -derivedDataPath "$DERIVED_ARM64" -showBuildSettings \
    | awk -F' = ' '/TARGET_BUILD_DIR/ {print $2; exit}'
)"
FULL_PRODUCT_NAME="$(
  xcodebuild -project FilmCan.xcodeproj -scheme FilmCan -configuration Release \
    -derivedDataPath "$DERIVED_ARM64" -showBuildSettings \
    | awk -F' = ' '/FULL_PRODUCT_NAME/ {print $2; exit}'
)"

APP_ARM64="${TARGET_BUILD_DIR}/${FULL_PRODUCT_NAME}"
APP_X86_64="${DERIVED_X86_64}/Build/Products/Release/${FULL_PRODUCT_NAME}"

if [ ! -d "$APP_ARM64" ]; then
  echo "error: Built arm64 app not found at ${APP_ARM64}"
  exit 1
fi
if [ ! -d "$APP_X86_64" ]; then
  echo "error: Built x86_64 app not found at ${APP_X86_64}"
  exit 1
fi

DIST_DIR="${ROOT_DIR}/dist"
STAGE_DIR="${DIST_DIR}/stage"
DMG_PATH="${DIST_DIR}/FilmCan.dmg"
DMG_TEMP="${DIST_DIR}/FilmCan-temp.dmg"
REPO_ROOT="$(git -C "$ROOT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
CUSTOMIZE_DMG=1
MOUNT_DIR=""
MOUNT_DEVICE=""

emit_version_json() {
  local app_plist="${APP_ARM64}/Contents/Info.plist"
  local version
  version="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$app_plist" 2>/dev/null \
    || defaults read "$app_plist" CFBundleShortVersionString 2>/dev/null)"
  if [ -z "$version" ]; then
    echo "warning: could not read version from ${app_plist} — website/version.json not updated" >&2
    return
  fi
  local versioned_dmg="FilmCan-${version}-universal.dmg"
  local versioned_dmg_path="${DIST_DIR}/${versioned_dmg}"
  cp "$DMG_PATH" "$versioned_dmg_path"
  echo "Created: ${versioned_dmg_path}"
  if [ -z "$REPO_ROOT" ]; then
    echo "warning: REPO_ROOT is empty (not a git repo?) — website/version.json not updated" >&2
    return
  fi
  local tag="Release_${version}"
  local out="${REPO_ROOT}/website/version.json"
  printf '{\n  "version": "%s",\n  "tag": "%s",\n  "dmg": "%s"\n}\n' \
    "$version" "$tag" "$versioned_dmg" > "$out"
  echo "Updated: ${out} (version=${version}, dmg=${versioned_dmg})"
}

sign_dmg_for_sparkle() {
  local dmg_path="$1"
  local sign_update_bin="${SPARKLE_SIGN_UPDATE_BIN:-$HOME/.sparkle-tools/bin/sign_update}"
  if [ ! -x "$sign_update_bin" ]; then
    echo "error: sign_update not found at ${sign_update_bin}." >&2
    echo "       Run the Sparkle keypair setup (see docs/superpowers/specs/2026-07-28-sparkle-auto-update-design.md, Task 2)" >&2
    echo "       or set SPARKLE_SIGN_UPDATE_BIN to its location." >&2
    exit 1
  fi
  "$sign_update_bin" "$dmg_path"
}

emit_appcast_entry() {
  local app_plist="${APP_ARM64}/Contents/Info.plist"
  local short_version build_number
  short_version="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" "$app_plist" 2>/dev/null)"
  build_number="$(/usr/libexec/PlistBuddy -c "Print CFBundleVersion" "$app_plist" 2>/dev/null)"
  if [ -z "$short_version" ] || [ -z "$build_number" ]; then
    echo "warning: could not read version from ${app_plist} — appcast.xml not updated" >&2
    return
  fi
  if [ -z "$REPO_ROOT" ]; then
    echo "warning: REPO_ROOT is empty (not a git repo?) — appcast.xml not updated" >&2
    return
  fi

  local versioned_dmg="FilmCan-${short_version}-universal.dmg"
  local tag="Release_${short_version}"
  local dmg_url="https://github.com/qtld88/FilmCan/releases/download/${tag}/${versioned_dmg}"
  local appcast_path="${REPO_ROOT}/website/appcast.xml"

  local sign_output
  sign_output="$(sign_dmg_for_sparkle "${DIST_DIR}/${versioned_dmg}")"
  local ed_signature length
  ed_signature="$(echo "$sign_output" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
  length="$(echo "$sign_output" | sed -n 's/.*length="\([^"]*\)".*/\1/p')"
  if [ -z "$ed_signature" ] || [ -z "$length" ]; then
    echo "error: could not parse sign_update output: ${sign_output}" >&2
    exit 1
  fi

  local notes
  notes="$(git -C "$REPO_ROOT" tag -l --format='%(contents)' "$tag")"
  if [ -z "$notes" ]; then
    notes="Release ${short_version}."
  fi

  local pub_date
  pub_date="$(date -u "+%a, %d %b %Y %H:%M:%S +0000")"

  "${ROOT_DIR}/scripts/append_appcast_entry.py" "$appcast_path" \
    "$build_number" "$short_version" "$dmg_url" "$ed_signature" "$length" "$pub_date" "$notes"
  echo "Updated: ${appcast_path} (version=${short_version}, build=${build_number})"
}

ensure_not_open() {
  local file="$1"
  if [ -e "$file" ] && lsof "$file" >/dev/null 2>&1; then
    echo "error: ${file} is in use. Close apps using it (Finder/Preview/Mail) and retry." >&2
    exit 1
  fi
}

wait_for_image_release() {
  local image="$1"
  for i in 1 2 3 4 5 6 7 8 9 10; do
    if ! hdiutil info | grep -F "$image" >/dev/null 2>&1; then
      return 0
    fi
    sleep "$SHORT_DELAY"
  done
  return 1
}

mounted_image_mount_point() {
  local image="$1"
  hdiutil info | awk -v image="$image" '
    $1=="image-path:" {img=$2}
    $1=="mount-point:" {mp=$2; if (img==image) {print mp; exit}}
  '
}

ensure_unmounted_image() {
  local image="$1"
  local mp
  mp="$(mounted_image_mount_point "$image")"
  if [ -n "$mp" ]; then
    hdiutil detach "$mp" >/dev/null 2>&1 || hdiutil detach -force "$mp" >/dev/null 2>&1 || true
  fi
  wait_for_image_release "$image" >/dev/null 2>&1 || true
}

create_udzo() {
  local image="$1"
  ensure_unmounted_image "$image"
  hdiutil create -volname "FilmCan" -srcfolder "$STAGE_DIR" -ov -format UDZO "$image"
}

create_udrw() {
    local image="$1"
  ensure_unmounted_image "$image"
  hdiutil create -volname "FilmCan" -srcfolder "$STAGE_DIR" -ov -format UDRW "$image"
}

ensure_not_open "$DMG_PATH"
ensure_not_open "$DMG_TEMP"
rm -rf "$STAGE_DIR"
mkdir -p "$STAGE_DIR"
cp -R "$APP_ARM64" "$STAGE_DIR/FilmCan.app"
ln -s /Applications "$STAGE_DIR/Applications"
if ! command -v osascript >/dev/null 2>&1; then
  CUSTOMIZE_DMG=0
fi

# Pick a python3 that can actually import PIL. A bare `python3` may resolve to
# Apple's /usr/bin/python3 (no Pillow) under a reduced/sandboxed PATH, which used
# to silently drop the DMG background. Scan likely interpreters first.
PIL_PYTHON=""
for candidate in \
  "${PIL_PYTHON_BIN:-}" \
  /opt/homebrew/bin/python3 \
  /usr/local/bin/python3 \
  "$HOME/.pyenv/shims/python3" \
  "$(command -v python3 2>/dev/null || true)"; do
  [ -n "$candidate" ] && [ -x "$candidate" ] || continue
  if "$candidate" -c "import PIL" >/dev/null 2>&1; then
    PIL_PYTHON="$candidate"
    break
  fi
done
if [ -z "$PIL_PYTHON" ]; then
  echo "warning: no python3 with Pillow found — DMG background will be skipped." >&2
  echo "         install Pillow (e.g. /opt/homebrew/bin/python3 -m pip install Pillow)" >&2
  echo "         or set PIL_PYTHON_BIN to a python3 that has it." >&2
  CUSTOMIZE_DMG=0
fi

mkdir -p "$STAGE_DIR/.background"
export DMG_BG_PATH="$STAGE_DIR/.background/background.png"
export DMG_BG_WIDTH=700
export DMG_BG_HEIGHT=520
export DMG_WINDOW_WIDTH=900
export DMG_WINDOW_HEIGHT=640
SHORT_DELAY="${SHORT_DELAY:-1}"
RETRY_DELAY="${RETRY_DELAY:-2}"
LONG_DELAY="${LONG_DELAY:-5}"

if [ "$CUSTOMIZE_DMG" -eq 1 ]; then
  if ! "$PIL_PYTHON" - <<'PY'
import os
from PIL import Image, ImageDraw, ImageFont

width = int(os.environ.get("DMG_BG_WIDTH", "700"))
height = int(os.environ.get("DMG_BG_HEIGHT", "520"))
bg = Image.new("RGB", (width, height), (255, 255, 255))
draw = ImageDraw.Draw(bg)

arrow_color = (140, 140, 140)
arrow_y = 260
arrow_start = (270, arrow_y)
arrow_end = (400, arrow_y)
draw.line([arrow_start, arrow_end], fill=arrow_color, width=4)
draw.polygon([(400, arrow_y), (388, arrow_y - 7), (388, arrow_y + 7)], fill=arrow_color)

def load_font(size):
    for path in [
        "/System/Library/Fonts/SFNS.ttf",
        "/System/Library/Fonts/Supplemental/Arial.ttf"
    ]:
        try:
            return ImageFont.truetype(path, size=size)
        except Exception:
            pass
    return ImageFont.load_default()

title_font = load_font(20)
body_font = load_font(14)

title = "Drag FilmCan to Applications"
body1 = "If macOS says it is not safe to open,"
body2 = "go to System Settings > Privacy & Security and click \"Open Anyway\"."

draw.text((width // 2, 70), title, fill=(40, 40, 40), font=title_font, anchor="mm")
draw.text((width // 2, 110), body1, fill=(70, 70, 70), font=body_font, anchor="mm")
draw.text((width // 2, 130), body2, fill=(70, 70, 70), font=body_font, anchor="mm")

bg.save(os.environ["DMG_BG_PATH"])
PY
  then
    CUSTOMIZE_DMG=0
  fi
fi

# Ensure bundled rsync resources exist in the staged app (copy from x86_64 build if missing)
RSYNC_STAGE_DIR="$STAGE_DIR/FilmCan.app/Contents/Resources/rsync"
RSYNC_X86_DIR="$APP_X86_64/Contents/Resources/rsync"
if [ ! -d "$RSYNC_STAGE_DIR/lib/x86_64" ] || [ ! -d "$RSYNC_STAGE_DIR/lib/arm64" ]; then
  if [ ! -d "$RSYNC_X86_DIR/lib/x86_64" ] && [ ! -d "$RSYNC_X86_DIR/lib/arm64" ]; then
    echo "error: No rsync resources found in either build." >&2
    exit 1
  fi
  rsync -a "$RSYNC_X86_DIR/" "$RSYNC_STAGE_DIR/"
fi

lipo -create \
  "$APP_ARM64/Contents/MacOS/FilmCan" \
  "$APP_X86_64/Contents/MacOS/FilmCan" \
  -output "$STAGE_DIR/FilmCan.app/Contents/MacOS/FilmCan"

# Re-sign bundled rsync binaries + dylibs (install_name_tool modifies signatures)
RSYNC_DIR="$STAGE_DIR/FilmCan.app/Contents/Resources/rsync"
if [ -d "$RSYNC_DIR" ]; then
  find "$RSYNC_DIR" -type f \( -name "rsync*" -o -name "*.dylib" \) -print0 \
    | xargs -0 -I{} codesign --force --sign "$SIGN_IDENTITY" "{}"
fi

codesign --force --deep --sign "$SIGN_IDENTITY" "$STAGE_DIR/FilmCan.app"
codesign --verify --deep --strict --verbose=2 "$STAGE_DIR/FilmCan.app"

# Assert the requirement is identity-based, not cdhash-based, so a signing change cannot
# silently revert to ad-hoc unnoticed.
if [ "$SIGN_IDENTITY" != "-" ]; then
  # codesign prints "# designated => X" when the requirement is implicit and a bare
  # "designated => X" when the signature carries an explicit one. Accept both.
  DR="$(codesign -d -r- "$STAGE_DIR/FilmCan.app" 2>&1 | sed -n 's/^#* *designated => //p')"
  echo "Designated requirement: ${DR}"
  case "$DR" in
    *cdhash*)
      echo "error: designated requirement is cdhash-based despite signing with" >&2
      echo "error: '${SIGN_IDENTITY_NAME}'. Saved tokens would be lost on update." >&2
      exit 1
      ;;
    *certificate*) ;;
    *)
      echo "error: unexpected designated requirement: ${DR}" >&2
      exit 1
      ;;
  esac
fi

rm -f "$DMG_PATH"
if [ "$CUSTOMIZE_DMG" -eq 0 ]; then
  create_udzo "$DMG_PATH"
  echo "Created: ${DMG_PATH}"
  emit_version_json
  emit_appcast_entry
  exit 0
fi

if ! create_udrw "$DMG_TEMP"; then
  CUSTOMIZE_DMG=0
fi

if [ "$CUSTOMIZE_DMG" -eq 1 ]; then
  ATTACH_INFO="$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_TEMP")"
  MOUNT_DIR="$(echo "$ATTACH_INFO" | awk '/\/Volumes\// {print $3; exit}')"
  MOUNT_DEVICE="$(echo "$ATTACH_INFO" | awk '/\/Volumes\// {print $1; exit}')"
  if [ -z "$MOUNT_DIR" ]; then
    CUSTOMIZE_DMG=0
  fi
fi

if [ "$CUSTOMIZE_DMG" -eq 1 ]; then
  AS_RESULT="$(
    osascript 2>/dev/null <<'EOF' || echo "fail"
set success to true
try
  tell application "Finder"
    tell disk "FilmCan"
      open
      delay 1
      set current view of container window to icon view
      set toolbar visible of container window to false
      set statusbar visible of container window to false
      set wStr to (do shell script "echo $DMG_WINDOW_WIDTH")
      if wStr is "" then set wStr to "900"
      set hStr to (do shell script "echo $DMG_WINDOW_HEIGHT")
      if hStr is "" then set hStr to "640"
      set w to wStr as integer
      set h to hStr as integer
      set the bounds of container window to {100, 100, 100 + w, 100 + h}
      set icon size of icon view options of container window to 110
      set arrangement of icon view options of container window to not arranged
      set background picture of icon view options of container window to file ".background:background.png"
      set position of item "FilmCan.app" of container window to {190, 260}
      set position of item "Applications" of container window to {520, 260}
      update without registering applications
      delay 2
      close
      delay 1
    end tell
  end tell
on error
  set success to false
end try
if success then
  return "ok"
else
  return "fail"
end if
EOF
  )"
  if [ "$AS_RESULT" != "ok" ]; then
    CUSTOMIZE_DMG=0
  fi
fi

if [ "$CUSTOMIZE_DMG" -eq 0 ]; then
  if [ -n "$MOUNT_DIR" ]; then
    hdiutil detach "$MOUNT_DIR" || true
  fi
  rm -f "$DMG_TEMP"
  create_udzo "$DMG_PATH"
  echo "Created: ${DMG_PATH}"
  emit_version_json
  emit_appcast_entry
  exit 0
fi

sync
DETACH_OK=0
for i in 1 2 3 4 5; do
  if [ -n "$MOUNT_DEVICE" ] && hdiutil detach "$MOUNT_DEVICE" >/dev/null 2>&1; then
    DETACH_OK=1
    break
  fi
  if hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1; then
    DETACH_OK=1
    break
  fi
  if [ -n "$MOUNT_DEVICE" ] && hdiutil detach -force "$MOUNT_DEVICE" >/dev/null 2>&1; then
    DETACH_OK=1
    break
  fi
  if hdiutil detach -force "$MOUNT_DIR" >/dev/null 2>&1; then
    DETACH_OK=1
    break
  fi
  sleep "$RETRY_DELAY"
done

if [ "$DETACH_OK" -ne 1 ]; then
  echo "warning: Could not detach image, forcing unmount..." >&2
  if [ -n "$MOUNT_DEVICE" ]; then
    diskutil unmount force "$MOUNT_DEVICE" >/dev/null 2>&1 || true
  fi
  diskutil unmount force "$MOUNT_DIR" >/dev/null 2>&1 || true
  killall Finder 2>/dev/null || true
  sleep "$RETRY_DELAY"
  if [ -n "$(mounted_image_mount_point "$DMG_TEMP")" ]; then
    echo "error: Failed to detach ${DMG_TEMP}" >&2
    rm -f "$DMG_TEMP"
    exit 1
  fi
fi

wait_for_image_release "$DMG_TEMP" || sleep "$LONG_DELAY"
sleep "$RETRY_DELAY"
CONVERT_OK=0
ensure_unmounted_image "$DMG_TEMP"
for i in 1 2 3 4 5; do
  if hdiutil convert "$DMG_TEMP" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG_PATH"; then
    CONVERT_OK=1
    break
  fi
  sleep "$RETRY_DELAY"
done

if [ "$CONVERT_OK" -ne 1 ]; then
  rm -f "$DMG_TEMP"
  create_udzo "$DMG_PATH"
  echo "Created: ${DMG_PATH}"
  emit_version_json
  emit_appcast_entry
  exit 0
fi

rm -f "$DMG_TEMP"

echo "Created: ${DMG_PATH}"
emit_version_json
emit_appcast_entry
