#!/bin/zsh
# Regenerates Resources/AppIcon.icns and docs/images/icon.png from scripts/icon/draw.swift.
set -euo pipefail
cd "${0:A:h}/../.."
TMP=$(mktemp -d)
trap "rm -rf '$TMP'" EXIT
swiftc -O scripts/icon/draw.swift -o "$TMP/draw"
mkdir -p "$TMP/AppIcon.iconset" Resources docs/images
for pt in 16 32 128 256 512; do
    "$TMP/draw" $pt "$TMP/AppIcon.iconset/icon_${pt}x${pt}.png"
    "$TMP/draw" $((pt * 2)) "$TMP/AppIcon.iconset/icon_${pt}x${pt}@2x.png"
done
iconutil -c icns "$TMP/AppIcon.iconset" -o Resources/AppIcon.icns
"$TMP/draw" 512 docs/images/icon.png
echo "Resources/AppIcon.icns, docs/images/icon.png"
