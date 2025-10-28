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

### Example

If you save `screen_recording.mov` to your Desktop:
- Original file: `screen_recording.mov` (100 MB)
- Compressed file: `screen_recording_compressed.mov` (25 MB)
- You'll get a notification: "Original: 100.0MB → Compressed: 25.0MB (75.0% savings)"

## Configuration

The service supports configurable video output formats through the `VIDEO_OUTPUT_FORMAT` environment variable.

### Output Format Options

- **4K** (default): Uses HandBrake's "Fast 2160p60" preset for 4K output
- **1080p**: Uses HandBrake's "Fast 1080p30" preset for Full HD output

Both presets use the following settings:
- H.264 encoder (x264)
- Quality: 22 (good balance between size and quality)
- Web optimized for faster streaming

### Changing the Output Format

To change from the default 4K to 1080p:

1. Edit the LaunchAgent plist file:
   ```bash
   nano ~/Library/LaunchAgents/com.desktop.video.compress.plist
   ```

2. Modify the `VIDEO_OUTPUT_FORMAT` value in the `EnvironmentVariables` section:
   ```xml
   <key>VIDEO_OUTPUT_FORMAT</key>
   <string>1080p</string>
   ```

3. Restart the service:
   ```bash
   launchctl unload ~/Library/LaunchAgents/com.desktop.video.compress.plist
   launchctl load ~/Library/LaunchAgents/com.desktop.video.compress.plist
   ```

### Manual Execution

When running the script manually, you can set the output format using an environment variable:

```bash
# Use 4K output (default)
python3 desktop_video_compress.py

# Use 1080p output
VIDEO_OUTPUT_FORMAT=1080p python3 desktop_video_compress.py
```

To further customize compression settings, edit `desktop_video_compress.py` and adjust the HandBrake command parameters.

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
