#!/bin/zsh
# Builds CutVR.app into ./dist
set -e
cd "$(dirname "$0")"
swift build -c release
APP=dist/CutVR.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/CutVR "$APP/Contents/MacOS/CutVR"
cp Icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>CutVR</string>
  <key>CFBundleDisplayName</key><string>CutVR</string>
  <key>CFBundleIdentifier</key><string>local.cutvr</string>
  <key>CFBundleExecutable</key><string>CutVR</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSRequiresAquaSystemAppearance</key><false/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "Done: $PWD/$APP"
