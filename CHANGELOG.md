# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Region screen recording: Shift + hold, drag, release to start recording; click the floating pill to stop.
- Recordings saved automatically as MP4 (HEVC video at native resolution, AAC system audio) to `~/Movies/HoldPicker`.
- Dashed outline around the recorded region and a timer pill placed in the corner farthest from it.
- Menu items: Stop Recording, Record System Audio, Open Recordings Folder, Change Recordings Folder.
- Quitting while recording finalizes the file before exiting.
- GitHub Actions CI: tests, a universal (arm64 + x86_64) release bundle and a downloadable zipped app on every push.
- `make install`, which copies the last bundle to `/Applications` without rebuilding.

### Fixed
- A gesture in progress is abandoned when macOS disables and re-enables the event tap, instead of leaving a stale overlay that captures the next click.
- `scripts/test.sh` no longer aborts under `set -u` on macOS's bash 3.2 when Xcode is the selected toolchain.

### Changed
- Renamed the app from HoldShot to HoldPicker (bundle identifier `dev.holdpicker.HoldPicker`).
- Shift is reserved for recording and removed from the trigger options.
- HoldPicker's own windows are excluded from every capture, so screenshots taken while recording are clean.

## [0.1.0] - 2026-09-22

### Added
- Press-and-hold gesture to start a screenshot selection anywhere on screen.
- Hold-and-replay event handling so ordinary clicks and drags are unaffected.
- Dimmed overlay with live selection frame and size label.
- Region capture through ScreenCaptureKit at native (Retina) resolution.
- Result copied to the clipboard as PNG and TIFF; nothing is written to disk.
- Menu bar item with enable/disable, trigger modifier, hold duration, sound and launch-at-login options.
- Escape cancels an in-progress selection.
