# Desktop Video Compress

Automatic Desktop Video Compression for macOS - A lightweight background service that watches your Desktop for video files and automatically compresses them using HandBrake CLI.

Perfect for screen recordings, video clips, and other videos that need to be optimized for web upload.

## Features

- 🎬 Automatically watches `~/Desktop` for new video files (`.mp4`, `.m4v`, `.mov`, `.avi`, `.mkv`, `.webm`, `.flv`, `.wmv`)
- 🗜️ Compresses videos using HandBrake CLI with web-optimized settings
- 🔔 Sends cross-platform desktop notifications when compression starts and finishes
- ✅ Checks for HandBrake CLI availability on startup
- 🚀 Runs automatically on login via LaunchAgent
- 📊 Shows compression statistics (original size, compressed size, savings %)
- 📝 Maintains logs in `~/Library/Logs/`

## Prerequisites

1. **Python 3** - Usually pre-installed on macOS, or install via:
   ```bash
   brew install python3
   ```

2. **HandBrake CLI** - Required for video compression:
   ```bash
   brew install handbrake
   ```

3. **Full Disk Access** (macOS only) - Required for moving files to trash:
   - Open **System Settings** > **Privacy & Security** > **Full Disk Access**
   - Click the **+** button and add your Python executable (usually `/usr/bin/python3` or `/opt/homebrew/bin/python3`)
   - The service will detect and warn you if this permission is missing

## Installation

1. Clone this repository:
   ```bash
   git clone https://github.com/matthewpick/desktop-video-compress.git
   cd desktop-video-compress
   ```

2. Run the installation script:
   ```bash
   ./install.sh
   ```

The installation script will:
- Install Python dependencies (watchdog, desktop-notifier)
- Create a LaunchAgent to run the service automatically
- Start the service immediately
- Configure it to start on login

You'll receive a notification when the service starts watching your Desktop.

## Usage

Once installed, the service runs automatically in the background. Simply:

1. Save or move a video file to your Desktop (supports `.mp4`, `.m4v`, `.mov`, `.avi`, `.mkv`, `.webm`, `.flv`, `.wmv`)
2. The service will detect it and start compression
3. You'll receive a notification when compression starts
4. When complete, you'll get a notification with compression statistics
5. The compressed file will be saved as `[original_name]_compressed.[extension]`
6. The original file will be automatically moved to the Trash

### Example

If you save `screen_recording.mov` to your Desktop:
- Original file: `screen_recording.mov` (100 MB)
- Compressed file: `screen_recording_compressed.mov` (25 MB)
- You'll get a notification: "Original: 100.0MB → Compressed: 25.0MB (75.0% savings)"
- Original file is moved to Trash automatically

## Configuration

The service uses HandBrake's "H.265 MKV 2160p60" preset with the following settings:
- H.265 encoder (x265) for better compression
- Quality: 22 (good balance between size and quality)
- 4K 60fps profile for high-quality content
- Web optimized for faster streaming

After compression, the original file is automatically moved to the Trash. You can restore it from the Trash if needed.

To modify compression settings, edit `desktop_video_compress.py` and adjust the HandBrake command parameters.

## Logs

Logs are stored in:
- `~/Library/Logs/desktop-video-compress.log` - Main application log
- `~/Library/Logs/desktop-video-compress-stdout.log` - Standard output
- `~/Library/Logs/desktop-video-compress-stderr.log` - Standard error

## Uninstallation

To stop and remove the service:

```bash
./uninstall.sh
```

This will:
- Stop the service
- Remove the LaunchAgent
- Keep the script files (in case you want to reinstall)

## Manual Control

### Start the service manually (for testing):
```bash
python3 desktop_video_compress.py
```

### Stop the service:
```bash
launchctl unload ~/Library/LaunchAgents/com.desktop.video.compress.plist
```

### Restart the service:
```bash
launchctl unload ~/Library/LaunchAgents/com.desktop.video.compress.plist
launchctl load ~/Library/LaunchAgents/com.desktop.video.compress.plist
```

## Troubleshooting

### "Insufficient access privileges" Error
If you see the error "Insufficient access privileges for operation" when the service tries to move files to trash, this means Python needs Full Disk Access permission on macOS.

**To fix:**
1. Open **System Settings** > **Privacy & Security** > **Full Disk Access**
2. Click the **+** button
3. Navigate to and select your Python executable:
   - Apple Silicon Mac: Usually `/opt/homebrew/bin/python3`
   - Intel Mac: Usually `/usr/local/bin/python3`
   - System Python: `/usr/bin/python3`
4. Toggle the switch to enable Full Disk Access
5. Restart the service:
   ```bash
   launchctl unload ~/Library/LaunchAgents/com.desktop.video.compress.plist
   launchctl load ~/Library/LaunchAgents/com.desktop.video.compress.plist
   ```

You can find your Python path by running:
```bash
which python3
```

The service will automatically check for this permission on startup and warn you in the logs if it's missing.

### HandBrake not found
If you get an error that HandBrake is not installed:
```bash
brew install handbrake
```

The service automatically searches for HandBrake in common locations:
- `/opt/homebrew/bin/handbrakecli` (Apple Silicon Mac)
- `/usr/local/bin/handbrakecli` (Intel Mac)
- `/usr/bin/handbrakecli` (Linux)

It checks for both `HandBrakeCLI` and `handbrakecli` executable names.

### Service not starting
Check the logs in `~/Library/Logs/` for error messages.

### No notifications
Make sure Python has permission to send notifications in System Preferences → Notifications.

**Note:** The script uses the `desktop-notifier` library for cross-platform notifications. If you're not seeing notifications, check that:
1. The service has permission to send notifications (System Preferences → Notifications)
2. The logs show "Notification sent" messages (check `~/Library/Logs/desktop-video-compress.log`)

### Files not being processed
- Check that the file is a supported video format (`.mp4`, `.m4v`, `.mov`, `.avi`, `.mkv`, `.webm`, `.flv`, `.wmv`)
- Check that the filename doesn't already contain `_compressed`
- Check the logs for errors

## License

MIT License - Feel free to use and modify as needed.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
