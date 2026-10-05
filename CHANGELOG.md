# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added
- Audio-only recording from the menu (**Record Audio Only**): records the computer's audio, for example the other people in a call, to an M4A.
- Region screen recording: Shift + hold, drag, release to start recording; click the floating pill to stop.
- Recordings saved automatically as MP4 (HEVC video at native resolution, AAC system audio) to `~/Movies/TedCat`.
- Dashed outline around the recorded region and a timer pill placed in the corner farthest from it.
- Menu items: Record Audio Only, Stop Recording, Include System Audio in Videos, Open Recordings Folder, Change Recordings Folder.
- The menu lists the two gestures, adapted to the chosen trigger modifier.
- Quitting while recording finalizes the file before exiting.
- After a recording is saved, a card in the same corner shows the file name, folder, size and length with a thumbnail. Click to play, drag the thumbnail into another app, or reveal it in Finder.
- GitHub Actions CI: tests, a universal (arm64 + x86_64) release bundle and a downloadable zipped app on every push.
- `make install`, which copies the last bundle to `/Applications` without rebuilding and without launching it, and prints the steps to grant permissions safely.

### Fixed
- A gesture in progress is abandoned when macOS disables and re-enables the event tap, instead of leaving a stale overlay that captures the next click.
- `scripts/test.sh` no longer aborts under `set -u` on macOS's bash 3.2 when Xcode is the selected toolchain.
- Launch at Login no longer silently snaps back off after TedCat is switched off under System Settings › General › Login Items. The menu item shows a mixed state, reads **Launch at Login: Allow in Login Items…** and opens Login Items, where only the user can turn it back on. Other failures are shown in an alert and logged with their error domain and code instead of being redacted.

### Changed
- Renamed the app from HoldShot to TedCat (bundle identifier `dev.tedcat.TedCat`), after Ted, the cat on the icon. Recordings now go to `~/Movies/TedCat`.
- App icon and menu bar glyph featuring Ted, generated into every required size at bundle time. While recording, the glyph's camera-lens eye turns red.
- Shift is reserved for recording and removed from the trigger options.
- TedCat's own windows are excluded from every capture, so screenshots taken while recording are clean.
- CI uses `actions/checkout@v7` and `actions/upload-artifact@v7`, which run on Node 24 instead of the deprecated Node 20.

## [0.1.0] - 2026-09-22

### Added
- Press-and-hold gesture to start a screenshot selection anywhere on screen.
- Hold-and-replay event handling so ordinary clicks and drags are unaffected.
- Dimmed overlay with live selection frame and size label.
- Region capture through ScreenCaptureKit at native (Retina) resolution.
- Result copied to the clipboard as PNG and TIFF; nothing is written to disk.
- Menu bar item with enable/disable, trigger modifier, hold duration, sound and launch-at-login options.
- Escape cancels an in-progress selection.
