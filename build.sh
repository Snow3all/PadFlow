#!/bin/zsh
# สร้าง PadFlow.app
set -e
cd "$(dirname "$0")"
APP=build/PadFlow.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp -R Resources/ "$APP/Contents/Resources/"
cp CREDITS.md LICENSE "$APP/Contents/Resources/"
swiftc -O -swift-version 5 -target arm64-apple-macos13 Sources/*.swift -o build/PadFlow-arm64 \
  -framework AppKit -framework GameController -framework IOBluetooth -framework SwiftUI -framework ServiceManagement -framework SceneKit
swiftc -O -swift-version 5 -target x86_64-apple-macos13 Sources/*.swift -o build/PadFlow-x86_64 \
  -framework AppKit -framework GameController -framework IOBluetooth -framework SwiftUI -framework ServiceManagement -framework SceneKit && \
  lipo -create build/PadFlow-arm64 build/PadFlow-x86_64 -output "$APP/Contents/MacOS/PadFlow" || \
  cp build/PadFlow-arm64 "$APP/Contents/MacOS/PadFlow"
rm -f build/PadFlow-arm64 build/PadFlow-x86_64
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>local.padmouse</string>
  <key>CFBundleName</key><string>PadFlow</string>
  <key>CFBundleExecutable</key><string>PadFlow</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSBluetoothAlwaysUsageDescription</key><string>PadFlow uses Bluetooth to turn off your controller when idle.</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundleDisplayName</key><string>PadFlow</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$APP"
echo "✅ Built $APP"
