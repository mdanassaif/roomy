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
if [ ! -f build/AppIcon.icns ] || [ makeicon.swift -nt build/AppIcon.icns ]; then
  swift makeicon.swift build/AppIcon.iconset
  iconutil -c icns build/AppIcon.iconset -o build/AppIcon.icns
fi
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Sign with a real identity so macOS remembers Roomy's permissions across rebuilds.
# An ad-hoc signature changes with every build, and macOS then asks for everything again.
IDENTITY=$(security find-identity -v -p codesigning | grep -m1 -oE '"(Developer ID Application|Apple Development)[^"]*"' | tr -d '"')
codesign --force --deep --sign "${IDENTITY:--}" "$APP"
rm -rf /Applications/Roomy.app
cp -R "$APP" /Applications/Roomy.app
echo "Installed /Applications/Roomy.app"
