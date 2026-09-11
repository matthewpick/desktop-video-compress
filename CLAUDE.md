# CLAUDE.md

This file provides guidance for Claude Code when working on this project.

## Project Overview

Desktop Video Compress is a macOS menu bar app (no Dock icon, `LSUIElement`) that watches a folder — the Desktop by default — and automatically re-encodes new videos to HEVC `.mp4` using AVFoundation.

It replaces an earlier Python + HandBrake + LaunchAgent implementation. **There is deliberately no external encoder dependency**: everything runs through `AVAssetReader`/`AVAssetWriter` and the hardware encoder. Don't reintroduce HandBrake, ffmpeg, or a Python fallback.

## Project Generation (XcodeGen)

The `.xcodeproj` is **generated** from `DesktopVideoCompress/project.yml` using
[XcodeGen](https://github.com/yonaskolb/xcodegen) and is **not** committed to git.
After a fresh clone — and any time `project.yml` changes — regenerate it before building:

```bash
make generate
# or directly:
xcodegen generate --spec DesktopVideoCompress/project.yml
```

Edit `DesktopVideoCompress/project.yml` (targets, build settings, entitlements, schemes) rather than the generated `project.pbxproj`. The Makefile build/test targets run `generate` automatically as a prerequisite.

Both `project.pbxproj` and `DesktopVideoCompress/DesktopVideoCompress/DesktopVideoCompress.entitlements` are generated and gitignored. Entitlements live under the target's `entitlements.properties` in `project.yml` — edit them there, not via Xcode's Signing & Capabilities UI (which would be overwritten on the next `generate`).

## Build Commands

```bash
make generate       # Generate .xcodeproj from project.yml
make build          # Release build
make build-debug    # Debug build
make test           # Run tests
make install        # Build and copy to /Applications
make dmg            # Create a distributable DMG
make clean          # Remove build artifacts
make bump-version V=0.1.1
```

Regenerate the app icon after changing the artwork script:

```bash
swift scripts/make-icon.swift
```

## Architecture

### Key Components

- **App/DesktopVideoCompressApp.swift** — `@main`, the `MenuBarExtra` and `Settings` scenes. Startup runs from the menu bar label's `.task`, which is the earliest point `NSAlert`/`NSOpenPanel` behave correctly for an `LSUIElement` app.
- **App/AppModel.swift** — `@Observable`; owns the watcher and wires up notifications, the login item, and the legacy migration.
- **Services/FolderWatcher.swift** — `FSEventStream` wrapper (file-level events, non-recursive) plus the candidate filters.
- **Services/FileStabilityMonitor.swift** — decides when a file has stopped being written. `StabilityTracker` is the pure, testable core.
- **Services/VideoCompressor.swift** — the `AVAssetReader` → `AVAssetWriter` pipeline. One instance per file.
- **Services/CompressionQueue.swift** — serial FIFO; owns progress, recent activity, and undo.
- **Services/NotificationService.swift** — `UNUserNotificationCenter` plus the reveal/undo actions.
- **Models/EncodeSettings.swift** — the bitrate ladder and downscale math, free of AVFoundation so it's directly testable.
- **Utilities/OutputNaming.swift** — output filename rules and the supported-extension list.
- **Utilities/ProcessedMarker.swift** — the `com.desktopvideocompress.processed` xattr.

### Data Flow

1. `FolderWatcher` emits a URL for anything created or changed in the watched folder
2. `CompressionQueue.enqueue` dedupes by path and appends a job
3. The drain loop waits for `FileStabilityMonitor`, then runs `VideoCompressor`
4. On success the temp file is moved into place, tagged, and the original is trashed
5. `CompletedJob` lands in `queue.completed`, which the menu renders and the notification reports

## Important Patterns

### Don't tear down the writer from `cancel()`

`VideoCompressor.cancel()` only raises a flag. Calling `writer.cancelWriting()` there makes AVFoundation stop invoking the `requestMediaDataWhenReady` block, so the sample pump never reaches `markAsFinished()` and `compress` deadlocks. The pump notices the flag on its next turn; `compress` tears things down afterward. There's a regression test for this.

### Never leave a partial file in the watched folder

Encodes go to a temp directory on the same volume (`.itemReplacementDirectory`) and are moved into place only on success. The final output name is resolved at move time, not before the encode, so a file that appeared meanwhile isn't clobbered.

### Guard against self-triggering

Output lands in the folder being watched. `ProcessedMarker` (an xattr) is the primary defense; `OutputNaming.looksLikeOurOutput` is a filename-based backstop for when the xattr is stripped by a sync client.

### Two skip guards

`VideoCompressor` returns `.alreadyEfficient` for HEVC sources at or below target. `CompressionQueue` discards output that saved less than `minimumSavingsFraction` (5%). Both mark the source as processed so it isn't reconsidered.

### Concurrency

`SWIFT_DEFAULT_ACTOR_ISOLATION` is deliberately **not** set to `MainActor` — the encoder is the core of the app and runs off the main actor. UI and state types are annotated `@MainActor` explicitly.

### Tests run inside the app host

`AppInfo.isRunningTests` suppresses startup side effects. Without it the legacy-migration `NSAlert` would block CI forever.

## Code Style

- SwiftUI for all views, no storyboards or XIBs
- `@Observable` (not `ObservableObject`) for state
- `os.Logger` for logging, subsystem = bundle ID
- Swift Testing (`import Testing`), not XCTest

## Testing

Tests are in `DesktopVideoCompressTests/`. `TestClipFactory` synthesizes real H.264/HEVC clips with `AVAssetWriter` so the compressor is exercised against actual bitstreams rather than mocks. Run with `make test`.

## CI/CD

- `.github/workflows/ci.yml` — build + test on PRs and main
- `.github/workflows/nightly.yml` — signed, notarized DMG to the rolling `nightly` prerelease on every main push
- `.github/workflows/release.yml` — on `v*` tags: signed, notarized, stapled DMG + attestation + GitHub Release + Homebrew cask update

Required repo secrets: `APPLE_CERTIFICATE_BASE64`, `APPLE_CERTIFICATE_PASSWORD`, `APPLE_TEAM_ID`, `APPLE_ID`, `APPLE_ID_PASSWORD`, `HOMEBREW_TAP_TOKEN`.

The release workflow pushes to `matthewpick/homebrew-desktop-video-compress`, which must exist before the first tag.
