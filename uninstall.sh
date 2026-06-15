#!/usr/bin/env bash
# Uninstall MiniMaxQuota.app.
# This script does NOT touch `mmx` itself or its config — those belong to the
# user. To fully remove mmx: `brew uninstall mmx-cli` or `npm uninstall -g mmx-cli`.
set -euo pipefail

APP_PATH="${1:-/Applications/MiniMaxQuota.app}"
USER_APP="$HOME/Applications/MiniMaxQuota.app"

removed_any=false
for path in "$APP_PATH" "$USER_APP"; do
    if [[ -d "$path" ]]; then
        echo "→ removing $path"
        rm -rf "$path"
        removed_any=true
    fi
done

if [[ "$removed_any" != "true" ]]; then
    echo "MiniMaxQuota.app not found at $APP_PATH or $USER_APP"
    echo "(nothing to remove)"
fi

# Kill the running process if any.
if pgrep -x MiniMaxQuota >/dev/null 2>&1; then
    echo "→ killing running MiniMaxQuota process"
    pkill -x MiniMaxQuota
fi

echo ""
echo "✓ MiniMaxQuota app removed."
echo "  Your mmx installation and ~/.mmx/config.json are untouched."
echo "  Run \`brew uninstall mmx-cli\` or \`npm uninstall -g mmx-cli\` separately if desired."
