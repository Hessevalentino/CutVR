#!/bin/zsh
# Builds CutVR.app into ./dist
set -e
cd "$(dirname "$0")"
# Universal binary: Apple Silicon + Intel
ARCHS=(--arch arm64 --arch x86_64)
swift build -c release "${ARCHS[@]}"
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/CutVR"
# Version = 1.0.<commit count>, identical locally and in CI (the updater compares it with release tags).
VERSION="${VERSION:-1.0.$(git rev-list --count HEAD 2>/dev/null || echo 0)}"
BUILD="${VERSION##*.}"
APP=dist/CutVR.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CutVR"
cp Icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>CutVR</string>
  <key>CFBundleDisplayName</key><string>CutVR</string>
  <key>CFBundleIdentifier</key><string>works.hesse.CutVR</string>
  <key>CFBundleExecutable</key><string>CutVR</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSRequiresAquaSystemAppearance</key><false/>
</dict></plist>
PLIST
# SIGN_IDENTITY set (e.g. "Developer ID Application: Valentino Hesse (395JXZ2H3J)") → signed with
# hardened runtime + secure timestamp, ready for notarization. Unset → ad-hoc signature for local use.
if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
else
  codesign --force --sign - "$APP"
fi
echo "Done: $PWD/$APP ($VERSION)"
