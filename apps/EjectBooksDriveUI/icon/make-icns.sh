#!/bin/bash
# Builds EjectBooksDrive.icns from the PNG masters in ./png.
# The PNGs were exported from icon-1024.svg; regenerate them only if the art changes.
# (The masters are named with "-2x" because "@" is not portable across the tooling that
#  produced them; iconutil requires "@2x", so this script renames on the way into the iconset.)
set -euo pipefail
cd "$(dirname "$0")"

SET=EjectBooksDrive.iconset
rm -rf "$SET"
mkdir -p "$SET"

for base in 16x16 32x32 128x128 256x256 512x512; do
  cp "png/icon_${base}.png"    "$SET/icon_${base}.png"
  cp "png/icon_${base}-2x.png" "$SET/icon_${base}@2x.png"
done

iconutil -c icns "$SET" -o EjectBooksDrive.icns
rm -rf "$SET"

echo "wrote $(pwd)/EjectBooksDrive.icns"
echo "next: cp EjectBooksDrive.icns ../../EjectBooksDrive.icns && ../build.sh"
