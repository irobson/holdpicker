# HoldShot

A tiny macOS menu bar app for region screenshots that go straight to your clipboard.

**Press and hold** the mouse button anywhere on screen. **Drag** to frame the area. **Release** to copy it.
No hotkey to remember, no file on disk, no window to dismiss.

- Instant: ScreenCaptureKit, native Retina resolution, ~0 ms overhead on normal clicks.
- Light: a single ~1 MB binary, no dependencies, no Dock icon, no background daemons.
- Objective: one gesture, one result. Everything else is optional.

## How it works

1. You press the primary mouse button and keep it still for **350 ms** (configurable).
2. The screen dims and a crosshair-free selection starts at the point you pressed.
3. Drag to size the rectangle. A label shows the size in points. Press **Esc** to abort.
4. Release the button. The area flashes briefly and the image is on your clipboard as PNG (and TIFF).

Ordinary clicks and drags are unaffected. HoldShot briefly holds back the mouse-down;
if you release or move before the hold timer fires, it replays the original event so
the app under the cursor sees exactly what you did. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the details.

If holding anywhere feels too eager for your workflow, pick a modifier in the menu
(for example **⌃ Control + Hold**): the gesture then only arms while that key is down.

## Requirements

- macOS 14 Sonoma or later.
- Two privacy grants, requested on first launch:
  - **Accessibility**: to intercept and re-inject mouse events.
  - **Screen Recording**: to read pixels with ScreenCaptureKit.

## Build and run

Swift 5.9+ toolchain. Xcode is not required; the Command Line Tools are enough.

```bash
make run        # development: run directly from the package
make bundle     # release build wrapped in build/HoldShot.app
make open       # bundle and launch
make test       # unit tests for the gesture logic
```

To install, copy `build/HoldShot.app` to `/Applications`.

### Code signing and permissions

The bundle is ad-hoc signed by default. macOS ties privacy grants to the app's
signature, so after a rebuild you may need to re-grant Accessibility. To keep the
grant stable across builds, sign with an identity from your keychain:

```bash
SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" make bundle
```

## Configuration

Everything is reachable from the menu bar icon.

| Setting          | Default   | Options                                  |
|------------------|-----------|------------------------------------------|
| Enabled          | on        | Pauses the event tap entirely when off   |
| Trigger          | Hold only | ⌃, ⌥, ⇧ or ⌘ + Hold                      |
| Hold Duration    | 350 ms    | 200, 350, 500, 750 ms                    |
| Play Sound       | off       | System "Pop" sound after each capture    |
| Launch at Login  | off       | Bundled app only                         |

The same values live in `UserDefaults` and can be scripted:

```bash
defaults write dev.holdshot.HoldShot holdDuration -float 0.5
defaults write dev.holdshot.HoldShot moveTolerance -float 6
defaults write dev.holdshot.HoldShot requiredModifiers -int 262144   # ⌃ Control
```

Modifier raw values: Control `262144`, Option `524288`, Shift `131072`, Command `1048576`.
Add them together to require more than one.

## Logs

```bash
log stream --predicate 'subsystem == "dev.holdshot.HoldShot"' --level debug
```

## Known limitations

- A selection is confined to the display where it started.
- The cursor does not change to a crosshair during selection; the dimmed overlay is the cue.
- Apps that rely on press-and-hold at the exact spot you press (Dock icons, scrubbing controls) will see the hold delay. Use a modifier trigger if that bothers you.
- Windows with secure input (password fields) still receive their events normally, but Esc-to-cancel is not available while such a field has focus.

## Roadmap

- Optional save-to-file with a configurable folder and naming pattern.
- Multi-display selections.
- Window-snapping selection (hover a window, click to capture it).
- Capture history in the menu.
- Preferences window and a proper app icon.

## Project layout

```
HoldShot/
├── Package.swift
├── Makefile
├── Resources/Info.plist          # bundle metadata (LSUIElement, bundle id)
├── scripts/
│   ├── bundle.sh                 # SwiftPM build -> .app
│   └── test.sh                   # swift test with CLT workaround
├── Sources/
│   ├── HoldShotCore/             # pure logic, no AppKit: gesture state machine, geometry
│   └── HoldShot/
│       ├── App/                  # entry point, app delegate, menu bar
│       ├── Capture/              # event tap, controller, ScreenCaptureKit, clipboard
│       ├── Overlay/              # selection window and layer-based view
│       └── Support/              # preferences, permissions, coordinates, logging
├── Tests/HoldShotCoreTests/
└── docs/ARCHITECTURE.md
```

## License

MIT. See [LICENSE](LICENSE).
