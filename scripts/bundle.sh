#!/bin/zsh
# Builds NotchMail.app into build/ (release, signed with a local identity, local use only).
# Usage: scripts/bundle.sh [--open]
set -euo pipefail
cd "${0:A:h}/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/NotchMail"
APP=build/NotchMail.app

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NotchMail"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>NotchMail</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>io.github.felixsbuehrm.notchmail</string>
    <key>CFBundleName</key><string>Notch Mail</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHumanReadableCopyright</key><string>MIT License.</string>
</dict>
</plist>
PLIST

# SIGN_IDENTITY="Developer ID Application: …" signs for distribution (hardened
# runtime, secure timestamp; notarize afterwards). Without it: local identity.
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
    scripts/signing.sh "$APP"
fi
echo "Built $APP"

if [[ "${1:-}" == "--open" ]]; then
    pkill -x NotchMail 2>/dev/null || true
    open "$APP"
fi
