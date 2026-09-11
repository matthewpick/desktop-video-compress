# Desktop Video Compress

A native macOS menu bar app that watches your Desktop and automatically compresses any video that lands there.

Drop in a screen recording, get back a much smaller HEVC `.mp4`. The original goes to the Trash, so your Desktop doesn't fill up with both copies.

No Homebrew packages, no Python, no HandBrake — everything runs through AVFoundation and the hardware video encoder built into your Mac.

## Features

- 🎬 Watches `~/Desktop` (or any folder you pick) for new videos
- 🗜️ Re-encodes to HEVC using the hardware encoder, in a web-optimized (faststart) `.mp4`
- ⏳ Waits for the file to finish being written — a 20-minute screen recording is only touched once it's done
- 🔔 Notifications on start and finish, with **Show in Finder** and **Undo** actions
- 📊 Menu bar shows live progress and recent activity with before/after sizes
- ↩️ One-click undo restores the original from the Trash
- 🛡️ Never makes a file bigger, and leaves already-efficient videos alone
- 🚀 Launches at login via `SMAppService`

## Requirements

macOS 14 (Sonoma) or later. Apple Silicon and Intel are both supported.

## Installation

```bash
brew install --cask matthewpick/desktop-video-compress/desktop-video-compress
```

Or download the `.dmg` from [Releases](https://github.com/matthewpick/desktop-video-compress/releases/latest), open it, and drag the app to Applications.

The app is signed with a Developer ID certificate and notarized by Apple, so it opens without a Gatekeeper warning.

### First launch

macOS will ask for permission to access your Desktop. Grant it — without it the app can't see the files it's meant to compress. You can change this later in **System Settings › Privacy & Security › Files and Folders**.

The app also asks to send notifications, and enables **Launch at login** for you. Both are togglable in Settings.

## Usage

Save or move a video to your Desktop. That's it.

1. The app notices the file and waits until it stops growing
2. You get a "Compressing…" notification, and the menu bar icon shows progress
3. When it finishes you get a notification like `12.4 MB → 3.1 MB (75% saved)`
4. The compressed `.mp4` sits on your Desktop; the original moves to the Trash

Click the menu bar icon for progress, recent activity, **Pause Watching**, and **Compress File…** for a one-off.

### Supported formats

`.mp4`, `.m4v`, and `.mov`.

Other containers — `.mkv`, `.webm`, `.flv`, `.wmv`, `.avi` — are **ignored**. AVFoundation can't demux them, and this app deliberately has no external encoder dependency. The old Python version listed those extensions but would have failed on them anyway.

### Output naming

The output is `<name>.mp4` next to the source. If that name is already taken — which it always is when the source is itself a `.mp4` — it becomes `<name>_compressed.mp4`, then `<name>_compressed-2.mp4`, and so on.

Output files are tagged with a `com.desktopvideocompress.processed` extended attribute so the app never re-compresses its own work, even if you rename the file.

## Settings

| Setting | Default | What it does |
|---|---|---|
| Watched folder | `~/Desktop` | Any folder you like |
| Compress files already in the folder at launch | Off | One pass over existing files on startup |
| Quality | Balanced | `Smaller file` (0.7×), `Balanced` (1×), `Higher quality` (1.5×) bitrate |
| Maximum size | Original | Optionally cap the longest edge at 4K / 1080p / 720p |
| Move the original to the Trash | On | Turn off to keep both files |
| Launch at login | On | Registered via `SMAppService` |
| Show notifications | On | |

### How the bitrate is chosen

Target bitrate is `pixels × 30 × bits-per-pixel × (fps/30)^0.7 × quality multiplier`, where bits-per-pixel steps down as resolution rises (0.10 at 720p, 0.08 at 1080p, 0.065 at 1440p, 0.05 at 4K+). Frame rate scales sub-linearly because consecutive frames are more similar the faster you sample.

Two guards apply:

- **Already efficient** — a source that's already HEVC at or below the target bitrate (and doesn't need downscaling) is left completely alone.
- **No worthwhile savings** — if the encode saves less than 5%, the output is discarded and the original stays put. The app will never hand you a bigger file.

## Logs

Everything goes to the unified log. To watch it live:

```bash
log stream --predicate 'subsystem == "com.desktopvideocompress.DesktopVideoCompress"' --level info
```

Or open Console.app and filter on `desktopvideocompress`.

## Building from source

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/xcodegen) (`brew install xcodegen`).

```bash
git clone https://github.com/matthewpick/desktop-video-compress.git
cd desktop-video-compress

make build       # Release build
make install     # Build and copy to /Applications
make test        # Run the test suite
make dmg         # Build a distributable DMG
```

The `.xcodeproj` is generated from `DesktopVideoCompress/project.yml` and is not committed. Run `make generate` after a fresh clone or any change to the spec; the `build`/`test` targets do it for you.

## Uninstalling

```bash
./uninstall.sh
```

Or `brew uninstall --cask desktop-video-compress`, then drag the app to the Trash. To also remove settings:

```bash
defaults delete com.desktopvideocompress.DesktopVideoCompress
```

## Migrating from the Python version

Earlier releases of this project were a Python script installed as a LaunchAgent. That version is gone — it needed `watchdog`, `desktop-notifier`, `Send2Trash`, and a Homebrew install of HandBrake, and it exited on startup if HandBrake was missing.

On first launch the app detects `~/Library/LaunchAgents/com.desktop.video.compress.plist` and offers to remove it. Accept — two services watching the same folder will fight over the same files. To do it by hand:

```bash
launchctl bootout gui/$UID/com.desktop.video.compress
rm ~/Library/LaunchAgents/com.desktop.video.compress.plist
```

Compression settings differ: the old version always used HandBrake's `Fast 2160p60 4K HEVC` preset at quality 22 regardless of the source. This one picks a bitrate from the source's actual resolution and frame rate.

## License

MIT License — feel free to use and modify as needed.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
