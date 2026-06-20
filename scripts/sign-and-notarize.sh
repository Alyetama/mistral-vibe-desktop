#!/bin/bash
# Sign with a Developer ID certificate, notarize with Apple, and staple the
# ticket — so the app opens with NO Gatekeeper warning, even when downloaded.
#
# Requirements:
#   - Apple Developer Program membership ($99/yr).
#   - A "Developer ID Application" certificate installed in your login keychain
#     (Xcode > Settings > Accounts > Manage Certificates, or developer.apple.com).
#
# One-time setup — store notarization credentials in a keychain profile:
#   xcrun notarytool store-credentials vibe-notary \
#     --apple-id "you@example.com" \
#     --team-id "YOURTEAMID" \
#     --password "app-specific-password"     # from appleid.apple.com, NOT your login password
#
# Usage:
#   SIGN_IDENTITY="Developer ID Application: Your Name (YOURTEAMID)" \
#   NOTARY_PROFILE="vibe-notary" \
#   ./scripts/sign-and-notarize.sh
#
# Find your signing identity with:  security find-identity -v -p codesigning
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Vibe"
APP="$ROOT/build/$APP_NAME.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$ROOT/Resources/Info.plist" 2>/dev/null || echo 1.0.0)"
DMG="$ROOT/dist/$APP_NAME-$VERSION.dmg"

: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your 'Developer ID Application: ... (TEAMID)' identity}"
NOTARY_PROFILE="${NOTARY_PROFILE:-vibe-notary}"

# 1. Build + sign the app with the Developer ID identity (hardened runtime).
echo "==> [1/6] Building and signing the app"
SIGN_IDENTITY="$SIGN_IDENTITY" bash "$ROOT/scripts/build.sh"

# 2. Notarize the app (submit a zip; the .app itself can't be uploaded directly).
echo "==> [2/6] Notarizing the app"
APP_ZIP="$(mktemp -u).zip"
ditto -c -k --keepParent "$APP" "$APP_ZIP"
xcrun notarytool submit "$APP_ZIP" --keychain-profile "$NOTARY_PROFILE" --wait
rm -f "$APP_ZIP"

# 3. Staple the ticket onto the app so it verifies offline.
echo "==> [3/6] Stapling the app"
xcrun stapler staple "$APP"

# 4. Package the stapled app into the styled DMG (no rebuild).
echo "==> [4/6] Packaging the DMG"
SKIP_BUILD=1 bash "$ROOT/scripts/make-dmg.sh"

# 5. Sign + notarize the DMG itself.
echo "==> [5/6] Signing and notarizing the DMG"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

# 6. Staple the DMG.
echo "==> [6/6] Stapling the DMG"
xcrun stapler staple "$DMG"

cp "$DMG" "$ROOT/dist/$APP_NAME.dmg"
echo
echo "Done. $DMG is signed, notarized, and stapled —"
echo "it will open with no Gatekeeper warning. Verify with:"
echo "  spctl -a -vvv -t install \"$DMG\""
echo "  codesign --verify --strict --verbose=2 \"$APP\""
