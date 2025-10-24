#!/bin/bash
# Demo script to show how desktop-video-compress works
# This script simulates the workflow without requiring HandBrake

set -e

echo "================================================"
echo "Desktop Video Compress - Demo Workflow"
echo "================================================"
echo ""

echo "This tool provides the following features:"
echo ""
echo "1. ✅ Automatically watches ~/Desktop for .mov files"
echo "2. ✅ Checks if HandBrake CLI is installed on startup"
echo "3. ✅ Sends macOS notification when compression starts"
echo "4. ✅ Compresses videos using HandBrake with web-optimized settings"
echo "5. ✅ Sends notification with compression stats when complete"
echo "6. ✅ Runs automatically on login via LaunchAgent"
echo "7. ✅ Easy installation with install.sh script"
echo ""

echo "================================================"
echo "Installation Process:"
echo "================================================"
echo ""
echo "1. Run: ./install.sh"
echo "   - Installs Python dependencies (watchdog)"
echo "   - Creates LaunchAgent for auto-start"
echo "   - Starts the service"
echo ""
echo "2. The service will:"
echo "   - Check if HandBrake CLI is installed"
echo "   - Show warning notification if not found"
echo "   - Exit with error if HandBrake is missing"
echo ""

echo "================================================"
echo "Usage:"
echo "================================================"
echo ""
echo "1. Save a .mov file to ~/Desktop"
echo "2. Notification: 'Starting compression of filename.mov'"
echo "3. HandBrake processes the video"
echo "4. Notification: 'Original: 100MB → Compressed: 25MB (75% savings)'"
echo "5. Compressed file saved as: filename_compressed.mov"
echo ""

echo "================================================"
echo "Requirements Check:"
echo "================================================"
echo ""

# Check Python
if command -v python3 &> /dev/null; then
    echo "✅ Python 3: $(python3 --version)"
else
    echo "❌ Python 3: Not found (required)"
fi

# Check pip
if command -v pip3 &> /dev/null; then
    echo "✅ pip3: Installed"
else
    echo "❌ pip3: Not found (required)"
fi

# Check HandBrake
if command -v HandBrakeCLI &> /dev/null; then
    echo "✅ HandBrake CLI: $(HandBrakeCLI --version 2>&1 | head -1)"
else
    echo "⚠️  HandBrake CLI: Not found"
    echo "   Install with: brew install handbrake"
fi

# Check watchdog
if python3 -c "import watchdog" 2>/dev/null; then
    echo "✅ watchdog: Installed"
else
    echo "⚠️  watchdog: Not installed"
    echo "   Install with: pip3 install watchdog"
fi

echo ""
echo "================================================"
echo "File Structure:"
echo "================================================"
echo ""
ls -lh | grep -v "^total" | awk '{print $9}' | while read file; do
    if [ -f "$file" ]; then
        case "$file" in
            *.py)
                echo "📄 $file - Python script"
                ;;
            *.sh)
                echo "🔧 $file - Shell script"
                ;;
            *.txt)
                echo "📋 $file - Configuration"
                ;;
            *.md)
                echo "📖 $file - Documentation"
                ;;
            *)
                echo "   $file"
                ;;
        esac
    fi
done

echo ""
echo "================================================"
echo "Next Steps:"
echo "================================================"
echo ""
echo "To install and start the service:"
echo "  ./install.sh"
echo ""
echo "To test without installing:"
echo "  python3 desktop_video_compress.py"
echo ""
echo "To uninstall:"
echo "  ./uninstall.sh"
echo ""
