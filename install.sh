#!/bin/bash
# Installation script for Desktop Video Compress

set -e

echo "Installing Desktop Video Compress..."

# Check if Python 3 is installed
if ! command -v python3 &> /dev/null; then
    echo "Error: Python 3 is not installed. Please install it first."
    exit 1
fi

# Check if pip is installed
if ! command -v pip3 &> /dev/null; then
    echo "Error: pip3 is not installed. Please install it first."
    exit 1
fi

# Install Python dependencies
echo "Installing Python dependencies..."
pip3 install -r requirements.txt

# Make the script executable
chmod +x desktop_video_compress.py

# Get the absolute path of the script
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/desktop_video_compress.py"

# Create LaunchAgent directory if it doesn't exist
mkdir -p ~/Library/LaunchAgents

# Create the plist file
PLIST_PATH="$HOME/Library/LaunchAgents/com.desktop.video.compress.plist"

cat > "$PLIST_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.desktop.video.compress</string>
    <key>ProgramArguments</key>
    <array>
        <string>$(which python3)</string>
        <string>$SCRIPT_PATH</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$HOME/Library/Logs/desktop-video-compress-stdout.log</string>
    <key>StandardErrorPath</key>
    <string>$HOME/Library/Logs/desktop-video-compress-stderr.log</string>
</dict>
</plist>
EOF

echo "LaunchAgent plist created at: $PLIST_PATH"

# Load the LaunchAgent
echo "Loading LaunchAgent..."
launchctl unload "$PLIST_PATH" 2>/dev/null || true
launchctl load "$PLIST_PATH"

echo ""
echo "✅ Installation complete!"
echo ""
echo "Desktop Video Compress is now running and will start automatically on login."
echo "It will watch ~/Desktop for .mov files and compress them using HandBrake."
echo ""
echo "To uninstall, run: ./uninstall.sh"
echo ""
echo "Note: Make sure HandBrake CLI is installed. If not, install it with:"
echo "  brew install handbrake"
