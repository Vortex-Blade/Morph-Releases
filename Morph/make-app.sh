#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
mkdir -p dist/Morph.app/Contents/MacOS dist/Morph.app/Contents/Resources
cp .build/release/Morph dist/Morph.app/Contents/MacOS/Morph
cp Assets/MorphIcon.png dist/Morph.app/Contents/Resources/MorphIcon.png
cat > dist/Morph.app/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Morph</string>
<key>CFBundleIdentifier</key><string>local.morph.converter</string>
<key>CFBundleName</key><string>Morph</string>
<key>CFBundleIconFile</key><string>Morph.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.1.0</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSAppleEventsUsageDescription</key><string>Morph leest geselecteerde Finder-bestanden om ze lokaal te converteren.</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# Generate a macOS iconset from the supplied 1024x1024 artwork.
ICONSET="$(mktemp -d)/Morph.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
  sips -s format png -z "$SIZE" "$SIZE" Assets/MorphIcon.png --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -s format png -z "$DOUBLE" "$DOUBLE" Assets/MorphIcon.png --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o dist/Morph.app/Contents/Resources/Morph.icns
rm -rf "$(dirname "$ICONSET")"
echo "Created dist/Morph.app with custom Morph icon"
