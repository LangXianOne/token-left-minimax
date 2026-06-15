#!/usr/bin/env bash
# Bundle MiniMaxQuota binary into a runnable .app for local use.
# Output: ./MiniMaxQuota.app
# Note: this is a *local* bundle (ad-hoc signed) — fine for personal use,
# not for distribution (would need a real Developer ID and notarization).
set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="MiniMaxQuota"
APP_BUNDLE_DIR="${APP_NAME}.app"
BIN_SRC=".build/debug/${APP_NAME}"
BIN_DST="${APP_BUNDLE_DIR}/Contents/MacOS/${APP_NAME}"

if [[ ! -x "${BIN_SRC}" ]]; then
    echo "error: ${BIN_SRC} not found — run 'swift build' first" >&2
    exit 1
fi

echo "→ removing old bundle"
rm -rf "${APP_BUNDLE_DIR}"

echo "→ creating bundle layout"
mkdir -p "${APP_BUNDLE_DIR}/Contents/MacOS"
mkdir -p "${APP_BUNDLE_DIR}/Contents/Resources"

echo "→ copying binary"
cp "${BIN_SRC}" "${BIN_DST}"
chmod +x "${BIN_DST}"

echo "→ writing Info.plist"
cat > "${APP_BUNDLE_DIR}/Contents/Info.plist" <<'PLIST'
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
codesign --force --sign - "${APP_BUNDLE_DIR}" 2>&1 | head -3 || echo "  (codesign unavailable, bundle still runnable)"

echo ""
echo "✓ built ${APP_BUNDLE_DIR}"
echo "  run with:  open ${APP_BUNDLE_DIR}"
