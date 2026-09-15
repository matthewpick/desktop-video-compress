#!/bin/bash
# Uninstall script for Desktop Video Compress

set -e

APP_NAME="Desktop Video Compress"
APP_PATH="/Applications/$APP_NAME.app"
BUNDLE_ID="com.desktopvideocompress.DesktopVideoCompress"
LEGACY_PLIST="$HOME/Library/LaunchAgents/com.desktop.video.compress.plist"

echo "Uninstalling $APP_NAME..."

# Quit the app if it's running. Unregistering the login item requires the app
# bundle to still exist, so do this before removing it.
if pgrep -f "$APP_PATH" > /dev/null 2>&1; then
    echo "Quitting $APP_NAME..."
    osascript -e "quit app \"$APP_NAME\"" 2>/dev/null || true
    sleep 1
fi

# Remove the login item registration.
if [ -d "$APP_PATH" ]; then
    echo "Removing login item..."
    /bin/launchctl bootout "gui/$UID/$BUNDLE_ID" 2>/dev/null || true

    echo "Removing $APP_PATH..."
    rm -rf "$APP_PATH"
else
    echo "App not found at $APP_PATH (may already be removed)"
fi

# Clean up the LaunchAgent from the old Python version, if it's still around.
if [ -f "$LEGACY_PLIST" ]; then
    echo "Removing the old Python LaunchAgent..."
    /bin/launchctl bootout "gui/$UID/com.desktop.video.compress" 2>/dev/null || true
    rm -f "$LEGACY_PLIST"
fi

echo ""
read -r -p "Also delete saved settings? [y/N] " reply
case "$reply" in
    [yY]*)
        defaults delete "$BUNDLE_ID" 2>/dev/null || true
        echo "Settings removed."
        ;;
    *)
        echo "Settings kept (remove later with: defaults delete $BUNDLE_ID)"
        ;;
esac

echo ""
echo "✅ Uninstall complete!"
echo ""
echo "Note: any videos already compressed are untouched, and originals remain"
echo "in the Trash until you empty it."
