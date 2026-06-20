#!/bin/bash
# Builds Vibe.app and packages it into a distributable .dmg with a
# drag-to-Applications layout. The bundled app is universal (Apple Silicon +
# Intel) unless ARCHS is overridden — see scripts/build.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Vibe"
APP="$ROOT/build/$APP_NAME.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ROOT/Resources/Info.plist" 2>/dev/null || echo 1.0.0)"
DMG="$ROOT/dist/$APP_NAME-$VERSION.dmg"
STAGE="$(mktemp -d)"
VOLNAME="$APP_NAME"

# 1. Build the app bundle.
bash "$ROOT/scripts/build.sh"

# 2. Stage the contents of the disk image.
echo "==> Staging disk image"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
[ -f "$ROOT/Resources/AppIcon.icns" ] && cp "$ROOT/Resources/AppIcon.icns" "$STAGE/.VolumeIcon.icns"
SetFile -a C "$STAGE" 2>/dev/null || true   # use the volume icon, if SetFile exists

# 3. Build a compressed read-only image.
echo "==> Creating $DMG"
mkdir -p "$ROOT/dist"
rm -f "$DMG"
hdiutil create \
  -volname "$VOLNAME" \
  -srcfolder "$STAGE" \
  -fs HFS+ \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "$DMG" >/dev/null

rm -rf "$STAGE"
echo "==> Done: $DMG"
echo "    $(du -h "$DMG" | cut -f1)  ·  $(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"
