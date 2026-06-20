#!/bin/bash
# Generates Resources/AppIcon.icns from an SVG using macOS built-in tools.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
SVG="$WORK/icon.svg"
ICONSET="$WORK/AppIcon.iconset"
mkdir -p "$ICONSET"

# Mistral-inspired stacked color bars on a rounded square.
cat > "$SVG" <<'EOF'
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#1a1a1a"/>
      <stop offset="1" stop-color="#000000"/>
    </linearGradient>
  </defs>
  <rect width="1024" height="1024" rx="224" fill="url(#bg)"/>
  <g transform="translate(232,300)">
    <rect x="0"   y="0"   width="112" height="112" fill="#FFD300"/>
    <rect x="112" y="0"   width="112" height="112" fill="#FFD300"/>
    <rect x="336" y="0"   width="112" height="112" fill="#FFD300"/>
    <rect x="448" y="0"   width="112" height="112" fill="#FFD300"/>

    <rect x="0"   y="112" width="112" height="112" fill="#FFAF00"/>
    <rect x="112" y="112" width="112" height="112" fill="#FF8205"/>
    <rect x="336" y="112" width="112" height="112" fill="#FF8205"/>
    <rect x="448" y="112" width="112" height="112" fill="#FA500F"/>

    <rect x="0"   y="224" width="112" height="112" fill="#FA500F"/>
    <rect x="112" y="224" width="112" height="112" fill="#FA500F"/>
    <rect x="224" y="224" width="112" height="112" fill="#E10500"/>
    <rect x="336" y="224" width="112" height="112" fill="#E10500"/>
    <rect x="448" y="224" width="112" height="112" fill="#E10500"/>

    <rect x="0"   y="336" width="112" height="112" fill="#E10500"/>
    <rect x="448" y="336" width="112" height="112" fill="#E10500"/>
  </g>
</svg>
EOF

# Prefer rsvg-convert / Inkscape if present; otherwise fall back to qlmanage.
render() { # $1 size  $2 out
  if command -v rsvg-convert >/dev/null 2>&1; then
    rsvg-convert -w "$1" -h "$1" "$SVG" -o "$2"
  elif command -v inkscape >/dev/null 2>&1; then
    inkscape "$SVG" -w "$1" -h "$1" -o "$2" >/dev/null 2>&1
  else
    # qlmanage renders SVG via QuickLook, then sips resizes.
    qlmanage -t -s 1024 -o "$WORK" "$SVG" >/dev/null 2>&1 || true
    local png="$WORK/icon.svg.png"
    [ -f "$png" ] || { echo "No SVG renderer available (install librsvg: brew install librsvg)"; exit 1; }
    sips -z "$1" "$1" "$png" --out "$2" >/dev/null
  fi
}

for s in 16 32 64 128 256 512 1024; do render "$s" "$WORK/$s.png"; done
cp "$WORK/16.png"   "$ICONSET/icon_16x16.png"
cp "$WORK/32.png"   "$ICONSET/icon_16x16@2x.png"
cp "$WORK/32.png"   "$ICONSET/icon_32x32.png"
cp "$WORK/64.png"   "$ICONSET/icon_32x32@2x.png"
cp "$WORK/128.png"  "$ICONSET/icon_128x128.png"
cp "$WORK/256.png"  "$ICONSET/icon_128x128@2x.png"
cp "$WORK/256.png"  "$ICONSET/icon_256x256.png"
cp "$WORK/512.png"  "$ICONSET/icon_256x256@2x.png"
cp "$WORK/512.png"  "$ICONSET/icon_512x512.png"
cp "$WORK/1024.png" "$ICONSET/icon_512x512@2x.png"

mkdir -p "$ROOT/Resources"
iconutil -c icns "$ICONSET" -o "$ROOT/Resources/AppIcon.icns"
echo "Wrote $ROOT/Resources/AppIcon.icns"
rm -rf "$WORK"
