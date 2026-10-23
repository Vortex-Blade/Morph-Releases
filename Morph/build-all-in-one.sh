#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Build dependencies are needed only on the builder's Mac, not on the user's Mac.
command -v swift >/dev/null || { echo "Xcode Command Line Tools ontbreken." >&2; exit 1; }
command -v python3 >/dev/null || { echo "Python 3 ontbreekt." >&2; exit 1; }
command -v otool >/dev/null || { echo "otool ontbreekt (Xcode Command Line Tools)." >&2; exit 1; }
command -v install_name_tool >/dev/null || { echo "install_name_tool ontbreekt." >&2; exit 1; }

locate_tool() {
  local name="$1"
  if command -v "$name" >/dev/null 2>&1; then command -v "$name"; return; fi
  for f in "/opt/homebrew/bin/$name" "/usr/local/bin/$name"; do
    if [ -x "$f" ]; then echo "$f"; return; fi
  done
  return 1
}

FFMPEG="$(locate_tool ffmpeg)" || { echo "Bouwvereiste: installeer eenmalig ffmpeg (brew install ffmpeg)." >&2; exit 1; }
QPDF="$(locate_tool qpdf)" || { echo "Bouwvereiste: installeer eenmalig qpdf (brew install qpdf)." >&2; exit 1; }
LO="${MORPH_LIBREOFFICE_APP:-/Applications/LibreOffice.app}"
[ -x "$LO/Contents/MacOS/soffice" ] || { echo "Bouwvereiste: LibreOffice.app ontbreekt op $LO" >&2; exit 1; }

bash make-app.sh
CONTENTS="$(pwd)/dist/Morph.app/Contents"
mkdir -p "$CONTENTS/Helpers" "$CONTENTS/Frameworks"
cp -L "$FFMPEG" "$CONTENTS/Helpers/ffmpeg"
cp -L "$QPDF" "$CONTENTS/Helpers/qpdf"
# Copy the complete app, not only soffice: it needs its own runtime, filters and assets.
ditto "$LO" "$CONTENTS/Helpers/LibreOffice.app"

python3 Scripts/bundle_dylibs.py "$CONTENTS" "$FFMPEG" "$QPDF"

# Ad-hoc signing makes the modified binaries locally launchable; notarization
# with an Apple Developer ID is needed for frictionless public distribution.
find "$CONTENTS/Frameworks" -type f -print0 | while IFS= read -r -d '' library; do
  codesign --force --sign - "$library"
done
codesign --force --deep --sign - "$(pwd)/dist/Morph.app"

# Check packaged helpers exist; verify external linkage of FFmpeg/qpdf.
for helper in ffmpeg qpdf; do
  [ -x "$CONTENTS/Helpers/$helper" ] || exit 1
  version_flag="--version"
  [ "$helper" = "ffmpeg" ] && version_flag="-version"
  "$CONTENTS/Helpers/$helper" "$version_flag" >/dev/null 2>&1 || {
    echo "WAARSCHUWING: $helper kon niet zelfstandig starten." >&2
    exit 1
  }
done
[ -x "$CONTENTS/Helpers/LibreOffice.app/Contents/MacOS/soffice" ] || exit 1

# Create a compressed, shareable disk image after successful packaging.
command -v diskutil >/dev/null || { echo "diskutil ontbreekt; DMG kan niet worden gemaakt." >&2; exit 1; }
DMG="$(pwd)/dist/Morph-1.1-Friends.dmg"
STAGING="$(mktemp -d)"
trap 'rm -rf "$STAGING"' EXIT
# Use a symlink so the DMG offers drag-and-drop installation.
ditto "$(pwd)/dist/Morph.app" "$STAGING/Morph.app"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
diskutil image create from --volumeName "Morph" --format UDZO "$STAGING" "$DMG"
hdiutil verify "$DMG"
echo "Morph All-in-One gereed: dist/Morph.app"
echo "DMG aangemaakt: dist/Morph-1.1-Friends.dmg"
echo "Test dit op een schone Mac zonder Homebrew of LibreOffice-installatie."
