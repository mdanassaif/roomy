#!/bin/bash
# Builds Roomy.app and installs it to /Applications
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/Roomy.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Roomy "$APP/Contents/MacOS/Roomy"
cp Info.plist "$APP/Contents/Info.plist"
if [ ! -f build/AppIcon.icns ]; then
  swift makeicon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"
rm -rf /Applications/Roomy.app
cp -R "$APP" /Applications/Roomy.app
echo "Installed /Applications/Roomy.app"
