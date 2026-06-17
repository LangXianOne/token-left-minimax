#!/usr/bin/env bash
# Build a release-style .app and zip it for sharing.
# Output: ./MiniMaxQuota-v<ver>.zip (version from Info.plist or hardcoded below)
#
# IMPORTANT: This bundle is ad-hoc signed. Recipients will need to
# right-click → Open the first time (or run `xattr -dr com.apple.quarantine ...`)
# because we don't have a real Apple Developer ID for notarization.
# For a frictionless install, see README → "Distribution" section.
set -euo pipefail

cd "$(dirname "$0")"

VERSION=$(plutil -extract CFBundleShortVersionString raw MiniMaxQuota.app/Contents/Info.plist 2>/dev/null || echo "0.2.0")
NAME="MiniMaxQuota"
ZIP="${NAME}-v${VERSION}.zip"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
MODULE_CACHE="$(pwd)/.build-modulecache"

# Clean previous artifacts
rm -rf "${NAME}.app" "${NAME}-v"*.zip
rm -rf .build-dist "${MODULE_CACHE}"
mkdir -p .build-dist "${MODULE_CACHE}"

echo "→ building release (optimized, direct swiftc)"
# We bypass `swift build` here because the SwiftPM driver in this environment
# invokes `sandbox-exec` to wrap the manifest compile, which fails inside
# nested sandboxes (e.g. when this script runs from a sandboxed shell).
# Direct swiftc is equivalent for a single-target executable package.
xcrun swiftc \
    -O \
    -target arm64-apple-macosx13.0 \
    -sdk "${SDK}" \
    -o ".build-dist/${NAME}" \
    Sources/${NAME}/*.swift

echo "→ assembling bundle"
mkdir -p "${NAME}.app/Contents/MacOS"
mkdir -p "${NAME}.app/Contents/Resources"
cp ".build-dist/${NAME}" "${NAME}.app/Contents/MacOS/${NAME}"
chmod +x "${NAME}.app/Contents/MacOS/${NAME}"
cp "Sources/MiniMaxQuota/Resources/MiniMaxQuota.icns" "${NAME}.app/Contents/Resources/MiniMaxQuota.icns"

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
    <string>0.2.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>MiniMaxQuota</string>
    <key>CFBundleIconFile</key>
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
