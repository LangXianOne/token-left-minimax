#!/usr/bin/env bash
# Build a release-style .app and zip it for sharing.
# Output: ./MiniMaxQuota-v0.1.0.zip
#
# IMPORTANT: This bundle is ad-hoc signed. Recipients will need to
# right-click → Open the first time (or run `xattr -dr com.apple.quarantine ...`)
# because we don't have a real Apple Developer ID for notarization.
# For a frictionless install, see README → "Distribution" section.
set -euo pipefail

cd "$(dirname "$0")"

VERSION=$(plutil -extract CFBundleShortVersionString raw MiniMaxQuota.app/Contents/Info.plist 2>/dev/null || echo "0.1.0")
NAME="MiniMaxQuota"
ZIP="${NAME}-v${VERSION}.zip"

echo "→ building release (optimized)"
swift build -c release 2>&1 | tail -3

echo "→ rebuilding bundle with release binary"
rm -rf "${NAME}.app"
mkdir -p "${NAME}.app/Contents/MacOS"
mkdir -p "${NAME}.app/Contents/Resources"
cp ".build/release/${NAME}" "${NAME}.app/Contents/MacOS/${NAME}"
chmod +x "${NAME}.app/Contents/MacOS/${NAME}"

cat > "${NAME}.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>MiniMaxQuota</string>
    <key>CFBundleDisplayName</key>
    <string>MiniMax Quota</string>
    <key>CFBundleIdentifier</key>
    <string>com.local.MiniMaxQuota</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>MiniMaxQuota</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

echo "→ ad-hoc signing"
codesign --force --deep --sign - "${NAME}.app" 2>&1 | head -3 || echo "  (codesign failed, bundle still zips)"

echo "→ zipping"
rm -f "${ZIP}"
# ditto preserves macOS-specific metadata (extended attributes, ACLs) better
# than `zip`, which matters for code signature resources.
ditto -c -k --sequesterRsrc --keepParent "${NAME}.app" "${ZIP}"

echo ""
echo "✓ built ${ZIP}"
ls -lh "${ZIP}"
echo ""
echo "Recipients on macOS will need to:"
echo "  1. unzip ${ZIP}"
echo "  2. drag MiniMaxQuota.app to /Applications"
echo "  3. first launch: right-click → Open (because ad-hoc signed)"
echo ""
echo "To skip the right-click step, run on the recipient machine:"
echo "  xattr -dr com.apple.quarantine /Applications/MiniMaxQuota.app"
