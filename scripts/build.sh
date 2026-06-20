#!/bin/bash
# Builds Vibe.app — a native WKWebView wrapper for Mistral Vibe (no Electron).
#
# By default it produces a universal binary that runs on both Apple Silicon and
# Intel Macs. Set ARCHS to override, e.g.:
#   ARCHS="arm64"          # Apple Silicon only
#   ARCHS="x86_64"         # Intel only
#   ARCHS="arm64 x86_64"   # universal (default)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Vibe"
APP="$ROOT/build/$APP_NAME.app"
MACOS="$APP/Contents/MacOS"
RES="$APP/Contents/Resources"
DEPLOY_TARGET="12.0"
ARCHS="${ARCHS:-arm64 x86_64}"

echo "==> Cleaning"
rm -rf "$APP"
mkdir -p "$MACOS" "$RES"

echo "==> Generating icon"
if [ ! -f "$ROOT/Resources/AppIcon.icns" ]; then
  bash "$ROOT/scripts/make-icon.sh" || echo "   (icon generation skipped)"
fi

echo "==> Compiling ($ARCHS, optimized)"
slices=()
for arch in $ARCHS; do
  slice="$ROOT/build/$APP_NAME-$arch"
  if swiftc \
      -O \
      -target "$arch-apple-macos$DEPLOY_TARGET" \
      -framework AppKit \
      -framework WebKit \
      -o "$slice" \
      "$ROOT/Sources/main.swift" 2>/dev/null; then
    slices+=("$slice")
    echo "    built $arch"
  else
    echo "    WARNING: could not build $arch slice — skipping"
  fi
done

if [ "${#slices[@]}" -eq 0 ]; then
  echo "ERROR: no architecture compiled successfully." >&2
  exit 1
fi

echo "==> Linking universal binary"
lipo -create -output "$MACOS/$APP_NAME" "${slices[@]}"
rm -f "${slices[@]}"
echo "    $(lipo -archs "$MACOS/$APP_NAME")"

echo "==> Assembling bundle"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
[ -f "$ROOT/Resources/AppIcon.icns" ] && cp "$ROOT/Resources/AppIcon.icns" "$RES/AppIcon.icns"

# Codesign. With a Developer ID identity in SIGN_IDENTITY, sign with the
# hardened runtime + secure timestamp (required for notarization). Otherwise
# fall back to an ad-hoc signature that only runs locally.
if [ -n "${SIGN_IDENTITY:-}" ]; then
  echo "==> Codesigning (Developer ID: $SIGN_IDENTITY)"
  codesign --force --deep --options runtime --timestamp \
    --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP" || true
else
  echo "==> Codesigning (ad-hoc — local use only)"
  codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || \
    echo "    (codesign skipped — app will still run)"
fi

echo "==> Done: $APP"
