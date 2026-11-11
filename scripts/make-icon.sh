#!/bin/bash
# Regenerates Resources/AppIcon.icns from scripts/make-icon.swift
set -euo pipefail
cd "$(dirname "$0")/.."

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

swift scripts/make-icon.swift "$WORK/icon-1024.png"

SET="$WORK/AppIcon.iconset"
mkdir "$SET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" "$WORK/icon-1024.png" --out "$SET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" "$WORK/icon-1024.png" --out "$SET/icon_${size}x${size}@2x.png" >/dev/null
done

iconutil -c icns "$SET" -o Resources/AppIcon.icns
cp "$WORK/icon-1024.png" Resources/AppIcon.png

echo "Wrote Resources/AppIcon.icns and Resources/AppIcon.png"
