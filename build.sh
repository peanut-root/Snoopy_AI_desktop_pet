#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/Snoopy Desktop.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -O -warnings-as-errors -swift-version 5 -target "$(uname -m)-apple-macos13.0" -framework AppKit -framework Network -framework ApplicationServices "$ROOT"/Sources/*.swift -o "$APP/Contents/MacOS/SnoopyDesktop"
cp -R "$ROOT/Assets" "$APP/Contents/Resources/"
# The app creates a private pairing token in the user's Application Support folder.
# Never embed the developer's local token in a redistributable app bundle.
rm -f "$APP/Contents/Resources/connection-token.txt"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>SnoopyDesktop</string>
<key>CFBundleIdentifier</key><string>local.snoopy.desktop</string>
<key>CFBundleName</key><string>Snoopy Desktop</string>
<key>CFBundleDisplayName</key><string>史努比桌宠</string>
<key>CFBundleVersion</key><string>25</string>
<key>CFBundleShortVersionString</key><string>1.9.2</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSAppleEventsUsageDescription</key><string>用于检测 ChatGPT 是否正在生成回答。</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP" >/dev/null
printf 'Built: %s\n' "$APP"
