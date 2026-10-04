# HoldPicker

[![CI](https://github.com/irobson/holdpicker/actions/workflows/ci.yml/badge.svg)](https://github.com/irobson/holdpicker/actions/workflows/ci.yml)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black)
![Swift 6](https://img.shields.io/badge/Swift-6-orange)
![Apple silicon and Intel](https://img.shields.io/badge/arch-arm64%20%7C%20x86__64-lightgrey)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A tiny macOS menu bar app that turns one mouse gesture into a region screenshot or a region screen recording.

| Gesture                              | Result                                                    |
|--------------------------------------|-----------------------------------------------------------|
| **Hold**, drag, release              | Screenshot of the region, copied to the clipboard         |
| **⇧ Shift + Hold**, drag, release    | Video of the region with system audio, saved as an MP4    |

No hotkey to remember, no window to dismiss, no account, no network access.

## Features

- **Press-and-hold to capture.** Hold the mouse button still for a moment anywhere on screen, then drag out the area you want.
- **Screenshots straight to the clipboard.** PNG and TIFF at native Retina resolution. Nothing is written to disk.
- **Region screen recording.** Shift + hold records just the selected area, with system audio, and saves it automatically.
- **Readable, light videos.** HEVC at native pixel density and 30 fps, with a bitrate that scales with the region size. Sharp enough to read code and slides, small enough to keep around, and ready for transcription tools.
- **Discreet controls.** A dashed outline marks the recorded area. A small timer pill sits in the screen corner farthest from it. One click stops and saves.
- **Clean output.** HoldPicker's own overlay, outline and pill never appear in screenshots or videos.
- **Ordinary clicks are untouched.** Quick clicks, double-clicks, drags and Shift-clicks reach your apps exactly as before.
- **Light.** One small native binary, no dependencies, no Dock icon, no background daemons.

## Installation

HoldPicker is not notarized yet, so you build it yourself or download a CI build.

### Build from source

Requirements: macOS 14 Sonoma or later, and a Swift 6 toolchain: Xcode 16 or later, or the Command Line Tools 16 or later (`xcode-select --install`).

```bash
git clone https://github.com/irobson/holdpicker.git
```

```bash
cd holdpicker
```

```bash
make bundle
```

```bash
make install
```

`make install` copies the app to `/Applications` and launches it. A camera icon appears in the menu bar.

### Download a CI build

Every push to `main` produces a universal app that runs on Apple silicon and Intel.

1. Open the latest successful [CI run](https://github.com/irobson/holdpicker/actions/workflows/ci.yml) and download the `HoldPicker-<commit>` artifact. Downloading artifacts requires a GitHub login.
2. GitHub wraps the artifact in its own zip. Unzip it, then unzip the `HoldPicker.zip` inside.
3. Move `HoldPicker.app` to `/Applications`.

The build is ad-hoc signed and not notarized, so macOS blocks the first launch.

- **macOS 15 and later:** open the app once and dismiss the warning. Then go to **System Settings › Privacy & Security**, scroll down and click **Open Anyway**.
- **macOS 14:** right-click the app, choose **Open**, then confirm.

If you prefer the terminal, removing the quarantine flag has the same effect:

```bash
xattr -dr com.apple.quarantine /Applications/HoldPicker.app
```

### Grant permissions

On first launch macOS asks for two permissions. HoldPicker cannot work without them.

| Permission                           | Why                                                        | Where                                                       |
|--------------------------------------|------------------------------------------------------------|-------------------------------------------------------------|
| **Accessibility**                    | To notice the press-and-hold and replay normal clicks      | System Settings › Privacy & Security › Accessibility        |
| **Screen & System Audio Recording**  | To read the pixels and the audio of the selected region    | System Settings › Privacy & Security › Screen & System Audio Recording. On macOS 14 the pane is called **Screen Recording** |

Turn **HoldPicker** on in both lists. If it is missing, click **+** and pick `/Applications/HoldPicker.app`.
macOS restarts the app after you grant screen recording. The menu bar menu also has shortcuts to both settings panes.

## Usage

### Take a screenshot

1. Press the mouse button and keep it **still** for about a third of a second.
2. The screen dims.
3. Drag to size the area. A white frame follows the pointer. A label shows its size in points. Press **Esc** to cancel.
4. Release. The area flashes and the image is on your clipboard.
5. Paste it anywhere with **⌘V**.

### Record the screen

1. Hold **⇧ Shift**, press the mouse button and keep it still for the same moment.
2. The screen dims and a **● REC** label appears where you pressed. You can let go of Shift now; the mode is fixed at the press.
3. Drag to size the area. The frame is **red**. Release, and recording starts immediately.
4. A dashed red outline marks what is being recorded. A small pill with a timer appears in a screen corner.
5. Click the pill to stop, or choose **Stop Recording** in the menu bar menu.
6. The pill shows **Saving…**, then turns green with **Saved**. Click it to reveal the file in Finder.

Recordings are saved to `~/Movies/HoldPicker/` with names like `HoldPicker 2026-10-04 at 14.03.22.mp4`.
Only one recording runs at a time. Screenshots keep working while you record.
Quitting HoldPicker during a recording saves the file before the app exits.

### Video format

| Track | Format                                                                      |
|-------|-----------------------------------------------------------------------------|
| Video | HEVC (H.265) in MP4, native pixel density, 30 fps, 1.5 to 6 Mbps by area size |
| Audio | AAC, 48 kHz stereo, 128 kbps. System audio, meaning what you hear          |

A full Retina screen comes to roughly 45 MB per minute. Window-sized areas are much smaller.
The microphone is not recorded.

To extract the audio for a transcription tool such as Whisper:

```bash
ffmpeg -i "HoldPicker 2026-10-04 at 14.03.22.mp4" -vn -ac 1 -ar 16000 audio.wav
```

### Things that keep working normally

HoldPicker briefly holds back each mouse press while it waits to see whether you are holding still. If you release or move before the hold time, it replays the original press, so:

- Clicks, double-clicks and drags behave as usual. A click registers on release instead of on press.
- Shift-click and Shift-drag, for example to extend a text selection or select several files, are unaffected.
- Moving the pointer slightly while pressing (up to 4 points) still counts as holding still.

## Settings

Everything is in the menu bar menu.

| Setting                    | Default                | Options                                                       |
|----------------------------|------------------------|---------------------------------------------------------------|
| Enabled                    | On                     | When off, HoldPicker does not touch any mouse event           |
| Trigger                    | Hold only              | ⌃ Control, ⌥ Option or ⌘ Command + Hold                       |
| Hold Duration              | 350 ms                 | 200, 350, 500 or 750 ms                                       |
| Play Sounds                | Off                    | Sounds on screenshot and on recording start and stop          |
| Launch at Login            | Off                    | Requires the app in a bundle, for example in `/Applications`  |
| Record System Audio        | On                     | Include what you hear in recordings                           |
| Recordings Folder          | `~/Movies/HoldPicker`  | Any folder, via **Change Recordings Folder…**                 |

If holding anywhere feels too eager, pick a trigger modifier. With **⌃ Control + Hold**, screenshots need ⌃ held and recordings need ⌃⇧. Shift is reserved for recording and cannot be the trigger.

The same settings live in `UserDefaults` and can be scripted:

```bash
defaults write dev.holdpicker.HoldPicker holdDuration -float 0.5
```

```bash
defaults write dev.holdpicker.HoldPicker moveTolerance -float 6
```

```bash
defaults write dev.holdpicker.HoldPicker recordingsFolder ~/Desktop
```

For a trigger modifier, pass an integer with `-int`: Control `262144`, Option `524288`, Command `1048576`. Add the values together to require more than one.

```bash
defaults write dev.holdpicker.HoldPicker requiredModifiers -int 262144
```

Gesture settings apply from the next press. The recordings folder applies from the next recording.

## Troubleshooting

**Nothing happens when I hold the mouse button.**
Accessibility is missing. The menu bar icon looks dimmed and the menu says *Waiting for Accessibility permission…*. Turn HoldPicker on under Accessibility; the app picks it up within two seconds.

**The pill says Failed, or the screenshot never reaches the clipboard.**
Screen recording permission is missing. Turn HoldPicker on under Screen & System Audio Recording, called Screen Recording on macOS 14, and let macOS restart it.

**The permission toggles are on, but it still fails.**
macOS ties permissions to the app's signature, and every rebuild of an ad-hoc signed app changes it. Reset both permissions, relaunch and grant them again:

```bash
tccutil reset Accessibility dev.holdpicker.HoldPicker
```

```bash
tccutil reset ScreenCapture dev.holdpicker.HoldPicker
```

To avoid this when building often, sign with a stable identity from your keychain:

```bash
SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" make bundle
```

**I want to see what HoldPicker is doing.**

```bash
log stream --predicate 'subsystem == "dev.holdpicker.HoldPicker"' --level debug
```

## Known limitations

- A selection stays on the display where it started.
- Recordings capture system audio only, not the microphone.
- The pointer does not turn into a crosshair during selection. The dimmed overlay is the cue.
- Controls that react to press-and-hold at the exact spot you press, such as Dock icons, feel the hold delay. A trigger modifier avoids that.
- Esc cannot cancel a selection while a secure text field, such as a password field, has focus.

## Privacy

HoldPicker has no network code. Screenshots go only to your clipboard and recordings only to the folder you choose. Nothing is collected or sent anywhere.

## Development

```bash
make run
```

```bash
make test
```

| Command        | What it does                                                         |
|----------------|----------------------------------------------------------------------|
| `make build`   | Debug build                                                          |
| `make run`     | Run straight from the package, without an app bundle                 |
| `make test`    | Unit tests for the gesture state machine and the video encoding plan. Uses Swift Testing, which ships with Swift 6 |
| `make bundle`  | Release build wrapped in `build/HoldPicker.app`. Add `UNIVERSAL=1` for arm64 + x86_64 (needs Xcode) |
| `make install` | Copy the last bundle to `/Applications` and launch it, without rebuilding |
| `make open`    | Bundle and launch from `build/`                                      |
| `make clean`   | Remove build products                                                |

`make install` deliberately never rebuilds, so the signature your permissions are tied to stays the same.

How the gesture detection, recording pipeline and coordinate handling work is described in [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

```
HoldPicker/
├── Package.swift
├── Makefile
├── Resources/Info.plist          # bundle metadata (menu bar only, bundle id)
├── scripts/
│   ├── bundle.sh                 # SwiftPM build into a signed .app
│   └── test.sh                   # swift test, with a Command Line Tools workaround
├── Sources/
│   ├── HoldPickerCore/           # pure logic: gesture state machine, geometry, encoding plan
│   └── HoldPicker/
│       ├── App/                  # entry point, app delegate, menu bar
│       ├── Capture/              # event tap, controller, screenshot capture, clipboard
│       ├── Recording/            # recorder, recording controller, outline, stop pill
│       ├── Overlay/              # selection window and layer-based view
│       └── Support/              # preferences, permissions, coordinates, logging
├── Tests/HoldPickerCoreTests/
├── docs/ARCHITECTURE.md
└── .github/workflows/ci.yml      # test and build a universal app on every push
```

## Roadmap

- Signed and notarized releases.
- Optional save-to-file for screenshots.
- Microphone track for recordings.
- Selections across multiple displays.

See the [issues](https://github.com/irobson/holdpicker/issues) for what is planned.

## License

MIT. See [LICENSE](LICENSE).
