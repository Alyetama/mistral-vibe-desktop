#!/bin/bash
# Builds Vibe.app and packages it into a styled, drag-to-install .dmg:
# a compact window with a branded background, an arrow, and the app and
# Applications icons positioned on either side.
#
# The bundled app is universal (Apple Silicon + Intel) unless ARCHS is
# overridden — see scripts/build.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Vibe"
APP="$ROOT/build/$APP_NAME.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ROOT/Resources/Info.plist" 2>/dev/null || echo 1.0.0)"
DMG="$ROOT/dist/$APP_NAME-$VERSION.dmg"
VOLNAME="$APP_NAME"
STAGE="$(mktemp -d)"
TMP_DMG="$(mktemp -u).dmg"

# Window + icon geometry (points).
WIN_W=600; WIN_H=420
WIN_L=200; WIN_T=120
ICON_SIZE=112
APP_X=150;  APP_Y=205     # app icon center (left)
APPS_X=450; APPS_Y=205    # Applications icon center (right)

cleanup() { rm -rf "$STAGE" "$TMP_DMG" 2>/dev/null || true; }
trap cleanup EXIT

# 1. Build the app bundle (skip with SKIP_BUILD=1 to package an existing,
#    already-signed/stapled build/Vibe.app as-is).
if [ "${SKIP_BUILD:-0}" = "1" ]; then
  [ -d "$APP" ] || { echo "ERROR: $APP not found (SKIP_BUILD=1 but no build)." >&2; exit 1; }
  echo "==> Skipping build (using existing $APP)"
else
  bash "$ROOT/scripts/build.sh"
fi

# 2. Render the background image (2x for Retina) from an inline SVG.
echo "==> Rendering background"
mkdir -p "$STAGE/.background"
BG_SVG="$STAGE/.background/background.svg"
cat > "$BG_SVG" <<SVG
<svg width="1200" height="840" viewBox="0 0 1200 840" xmlns="http://www.w3.org/2000/svg"
     font-family="Helvetica Neue, Helvetica, Arial, sans-serif">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#1d1207"/>
      <stop offset="0.55" stop-color="#0f0c0b"/>
      <stop offset="1" stop-color="#090809"/>
    </linearGradient>
    <radialGradient id="glow" cx="0.5" cy="0.16" r="0.7">
      <stop offset="0" stop-color="#fa500f" stop-opacity="0.20"/>
      <stop offset="1" stop-color="#fa500f" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="arrow" x1="0" y1="0" x2="1" y2="0">
      <stop offset="0" stop-color="#ff8a1e"/>
      <stop offset="1" stop-color="#fa3d0f"/>
    </linearGradient>
  </defs>
  <rect width="1200" height="840" fill="url(#bg)"/>
  <rect width="1200" height="840" fill="url(#glow)"/>

  <text x="600" y="150" text-anchor="middle" fill="#f3f3f3" font-size="46" font-weight="700">Install Vibe</text>
  <text x="600" y="196" text-anchor="middle" fill="#9a9a9a" font-size="23">Drag the app onto the Applications folder</text>

  <!-- arrow between the two icons (icons are drawn by Finder) -->
  <g stroke="url(#arrow)" fill="none" stroke-width="13" stroke-linecap="round" stroke-linejoin="round">
    <line x1="470" y1="410" x2="730" y2="410"/>
    <polyline points="690,378 732,410 690,442"/>
  </g>

  <text x="600" y="720" text-anchor="middle" fill="#6f6f6f" font-size="19">Vibe — a native, no-Electron desktop app for Mistral Vibe</text>
</svg>
SVG

if command -v rsvg-convert >/dev/null 2>&1; then
  rsvg-convert -w 1200 -h 840 "$BG_SVG" -o "$STAGE/.background/background.png"
else
  qlmanage -t -s 1200 -o "$STAGE/.background" "$BG_SVG" >/dev/null 2>&1 || true
  [ -f "$STAGE/.background/background.svg.png" ] && mv "$STAGE/.background/background.svg.png" "$STAGE/.background/background.png"
fi
rm -f "$BG_SVG"
# Tag the 1200x840 image at 144 DPI so Finder maps it to a 600x420-point
# window (= WIN_W x WIN_H) while keeping it crisp on Retina (2x).
sips -s dpiWidth 144 -s dpiHeight 144 "$STAGE/.background/background.png" >/dev/null 2>&1 || true

# 3. Stage the disk image contents.
echo "==> Staging"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
[ -f "$ROOT/Resources/AppIcon.icns" ] && cp "$ROOT/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"

# 4. Create a read-write image we can lay out in Finder.
echo "==> Creating writable image"
rm -f "$TMP_DMG"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -fs HFS+ \
  -format UDRW -size 64m -ov "$TMP_DMG" >/dev/null

hdiutil detach "/Volumes/$VOLNAME" >/dev/null 2>&1 || true
MOUNT_DIR="$(hdiutil attach "$TMP_DMG" -nobrowse -noautoopen | grep -Eo '/Volumes/[^"]+' | head -1)"
SetFile -a C "$MOUNT_DIR" 2>/dev/null || true   # use the custom volume icon

# 5. Lay out the window with Finder (background, size, icon positions).
echo "==> Styling window"
LAYOUT_OK=1
osascript <<APPLESCRIPT 2>/dev/null || LAYOUT_OK=0
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {$WIN_L, $WIN_T, $((WIN_L + WIN_W)), $((WIN_T + WIN_H))}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to $ICON_SIZE
    set text size of opts to 13
    set background picture of opts to file ".background:background.png"
    set position of item "$APP_NAME.app" of container window to {$APP_X, $APP_Y}
    set position of item "Applications" of container window to {$APPS_X, $APPS_Y}
    update without registering applications
    delay 1
    close
  end tell
end tell
APPLESCRIPT

if [ "$LAYOUT_OK" -eq 1 ]; then
  echo "    layout applied"
else
  echo "    WARNING: Finder layout was blocked (Automation permission)."
  echo "    The DMG still works, but the styled window/background won't show."
  echo "    Re-run this script from Terminal and approve the 'control Finder' prompt."
fi

sync
hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true

# 6. Convert to a compressed, read-only image.
echo "==> Compressing"
mkdir -p "$ROOT/dist"
rm -f "$DMG"
hdiutil convert "$TMP_DMG" -format UDZO -imagekey zlib-level=9 -ov -o "$DMG" >/dev/null

echo "==> Done: $DMG"
echo "    $(du -h "$DMG" | cut -f1)  ·  $(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"
