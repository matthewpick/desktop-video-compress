#!/bin/bash
# Uninstall script for Desktop Video Compress

set -e

echo "Uninstalling Desktop Video Compress..."

PLIST_PATH="$HOME/Library/LaunchAgents/com.desktop.video.compress.plist"

# Unload the LaunchAgent
if [ -f "$PLIST_PATH" ]; then
    echo "Unloading LaunchAgent..."
    launchctl unload "$PLIST_PATH" 2>/dev/null || true
    rm "$PLIST_PATH"
    echo "LaunchAgent removed"
else
    echo "LaunchAgent not found (may not be installed)"
fi

echo ""
echo "✅ Uninstall complete!"
echo ""
echo "Desktop Video Compress has been stopped and will no longer start automatically."
echo "The script files are still in this directory if you want to reinstall later."
