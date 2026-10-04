# Architecture

HoldPicker is small on purpose. This document explains the parts that are not
obvious from reading the code top to bottom: the event interception trick, the
coordinate systems, and why each module is where it is.

## Pipeline

```
 CGEvent tap (session level, active)
        │  leftMouseDown / Dragged / Up, keyDown
        ▼
 CaptureController.handle(type:event:)
        │  converts to PointerInput
        ▼
 HoldGestureRecognizer.handle(_:)  ──► Response { verdict, effects }
        │
        ├─ verdict ─► pass / swallow / hold / release   (what to do with this CGEvent)
        │
        └─ effects ─► armTimer / disarmTimer
                      beginSelection(mode) ─► SelectionOverlayWindow.show()
                      updateSelection ─► overlay.setSelection(cgRect:)
                      commitSelection(.screenshot) ─► ScreenCapturer.capture(...) ─► Clipboard.write(...)
                      commitSelection(.recording)  ─► RecordingController.start(...) ─► ScreenRecorder
                      cancelSelection ─► overlay.dismiss()
```

The modifiers held at mouse-down decide the `CaptureMode`. Shift (on top of any
configured trigger modifier) means `.recording`. The recognizer carries the mode
from `pending` through `selecting` to `commitSelection`, so it cannot change mid-gesture
if the user lets go of Shift while dragging.

The gesture pipeline and all UI run on the main actor. The tap's run loop source
is attached to the main run loop, the hold timer is a `DispatchWorkItem` on the
main queue, and AppKit is main-thread only anyway.

The one exception is `ScreenRecorder`. It receives sample buffers and drives
`AVAssetWriter` on its own serial queue (`dev.holdpicker.recorder`), and all of
its mutable state is confined to that queue. It talks back to the main actor only
through `onUnexpectedStop`, dispatched to the main queue.

## Hold-and-replay

The hard problem: how do you detect "press and hold" on *any* pixel without
breaking every other press?

An active `CGEvent` tap must decide synchronously, per event, whether to pass or
drop it. When the mouse-down arrives we do not yet know whether it will become a
hold. If we pass it through and it turns out to be a hold, the app underneath has
already received a mouse-down and will get a mouse-up it did not expect, or none
at all. If we drop it and it turns out to be a normal click, the click is lost.

So we do neither: the mouse-down is **held** (dropped, but a copy is kept) and a
timer is armed.

| Then…                                   | We do…                                                                 |
|-----------------------------------------|------------------------------------------------------------------------|
| Mouse-up arrives before the timer       | Replay the held mouse-down, then replay the mouse-up. Normal click.    |
| Pointer moves past the tolerance        | Replay the held mouse-down, then the drag. Normal drag from here on.   |
| Timer fires first                       | Enter selection mode. The held event is discarded; the app never sees it. |

Replayed events are posted at the HID level (`CGEvent.post(tap: .cghidEventTap)`),
so they travel the same path as real input and reach the app in order. They carry
a marker in `eventSourceUserData` so our own tap lets them through untouched.

The user-visible cost is that a plain click registers on release instead of on
press, a few tens of milliseconds later. Double-clicks keep working because the
replayed copy preserves the original click count.

The recognizer itself (`HoldPickerCore/HoldGestureRecognizer.swift`) is a pure
state machine. It owns no timer and touches no I/O; it just returns what should
happen. That is what makes it unit-testable without a window server.

```
 idle ──down──► pending ──timeout──► selecting ──up──► idle
                  │  │  │
                  │  │  └──up──► (replay down + up) ──► idle
                  │  └──move > tolerance──► (replay down + drag) ──► passthrough ──up──► idle
                  │
                  └──(trigger modifier missing, or recording busy)──► pass, stay idle
```

If macOS disables the event tap (it does so when a callback is too slow), events
are lost while it is off. `EventTap` re-enables itself and calls `onReenabled`;
the controller then abandons any gesture in progress. The held mouse-down is
dropped rather than replayed, because its mouse-up may already have gone through
and a lone replayed mouse-down would leave the button stuck in the target app.

## Coordinate systems

Two systems meet in this app:

- **CG / global display space**: `CGEvent.location`, `CGDisplayBounds`,
  `SCDisplay.frame` and `SCStreamConfiguration.sourceRect`. Origin at the
  top-left of the primary display, y grows down.
- **Cocoa space**: `NSScreen.frame`, `NSWindow.frame`, view geometry. Origin at
  the bottom-left of the primary display, y grows up.

`ScreenGeometry` holds the conversions. The recognizer works entirely in CG space
(it just does arithmetic on the points the tap gives it). The overlay window
converts once when it receives a rectangle. ScreenCaptureKit wants the rectangle
relative to its display's own top-left corner, so `ScreenCapturer` subtracts the
display origin before capturing.

Retina is handled by asking the content filter for its `pointPixelScale` and
requesting an output size of `points × scale`. The bitmap written to the
pasteboard has its `size` set back to points so it pastes at 1:1.

## Recording

`ScreenRecorder` is a straight pipe with no intermediate buffering:

```
 SCStream (region, 30 fps, BGRA + 48 kHz PCM)
        │  CMSampleBuffer on a private serial queue
        ▼
 AVAssetWriter (.mp4)
        ├─ video input: HEVC, bitrate from VideoEncodingPlan
        └─ audio input: AAC 128 kbps
```

Details worth knowing:

- **Size and bitrate** come from `HoldPickerCore/VideoEncodingPlan`: native pixels
  (points × backing scale), rounded down to even dimensions for 4:2:0 encoding,
  and `0.04 bits/pixel/frame` clamped to 1.5–6 Mbps. Pure and unit-tested.
- **Session timing.** The writer session starts at the first *complete* video
  frame; idle/blank status buffers from ScreenCaptureKit are skipped, and audio
  before that instant is dropped so tracks start together.
- **Static screens.** ScreenCaptureKit only delivers frames when pixels change. On
  stop, the last frame is re-stamped at "now" so the video lasts as long as the
  recording the user saw. "Now" is expressed in the stream's clock via an offset
  measured at the first frame, so no assumption is made about which clock the
  stream uses.
- **Own UI excluded.** `CaptureFilter` excludes every window owned by our process
  (matched by PID, so `swift run` works too). The outline, pill and overlay never
  appear in output, and screenshots taken during a recording are clean as well.
- **One at a time.** While `RecordingController.isBusy`, the controller hands the
  recognizer `allowsRecording = false`, so ⇧ + Hold passes through as a normal press.
- **Never lose a file.** `applicationShouldTerminate` returns `.terminateLater`
  while busy and replies once the file is finalized. If the stream dies on its own
  (display unplugged, permission revoked) the delegate triggers the same stop path,
  so whatever was captured is saved.
- **Never leave junk.** `startWriting` creates the file, so it runs only after
  everything that can throw during setup; if `startCapture` then fails, the file is
  discarded. If the writer fails mid-recording (disk full, encoder error), the
  failure is reported at once instead of the timer silently running on, and the
  unplayable partial file is removed.

## Overlay

`SelectionOverlayWindow` is a borderless, transparent, click-through window at
`.screenSaver` level covering the screen where the gesture began. It joins all
Spaces and full-screen apps. Because `ignoresMouseEvents` is on, it never
competes with the event tap for input; the controller pushes rectangles in.

`SelectionOverlayView` is layer-backed and never draws. Four dim layers frame the
selection, two border layers give a white line with a dark outline that stays
visible over any background, and a `CATextLayer` shows the size. Updating the
selection only moves layer frames inside a transaction with implicit animations
disabled, so it stays smooth at high pointer report rates.

Our whole process is excluded from capture (see `CaptureFilter`), so the
result never contains the dimming or the frame even though the flash animation
is still on screen while the capture runs. In recording mode the frame is red
and the label carries a REC prefix.

## Permissions

- **Accessibility** is required to create an active tap (`.defaultTap`). If the
  tap cannot be created, the controller reports `.needsAccessibility` and retries
  every two seconds, so granting the permission in System Settings brings the app
  to life without a restart.
- **Screen Recording** is requested at launch through `CGRequestScreenCaptureAccess`.
  ScreenCaptureKit will fail the capture if it is missing; the error is logged.

Both grants are keyed to the app's code signature. The bundle script ad-hoc signs
by default, which changes on every build. `SIGN_IDENTITY` lets you use a stable
identity.

## Module map

| Path                                      | Responsibility                                                         |
|-------------------------------------------|------------------------------------------------------------------------|
| `HoldPickerCore/HoldGestureRecognizer.swift`| Gesture state machine. Pure, tested.                                   |
| `HoldPickerCore/Geometry.swift`             | Rect normalization and clamping helpers.                               |
| `HoldPicker/App/HoldPickerApp.swift`          | `@main` entry; sets accessory activation policy.                       |
| `HoldPicker/App/AppDelegate.swift`          | Wires controller and menu; handles termination.                        |
| `HoldPicker/App/StatusBarController.swift`  | Menu bar item, all user-facing settings.                               |
| `HoldPicker/Capture/EventTap.swift`         | `CGEvent` tap wrapper; re-enables itself after timeouts.               |
| `HoldPicker/Capture/CGEvent+Replay.swift`   | Synthetic marker and HID-level replay.                                 |
| `HoldPicker/Capture/CaptureController.swift`| Orchestrates tap, recognizer, timer, overlay, capture, clipboard.      |
| `HoldPicker/Capture/CaptureFilter.swift`    | Shared `SCContentFilter` that excludes our own windows; rect conversion. |
| `HoldPicker/Capture/ScreenCapturer.swift`   | ScreenCaptureKit region screenshot.                                    |
| `HoldPickerCore/VideoEncodingPlan.swift`    | Output pixel size and bitrate for a recording. Pure, tested.           |
| `HoldPicker/Recording/ScreenRecorder.swift` | `SCStream` → `AVAssetWriter` region recording to MP4.                  |
| `HoldPicker/Recording/RecordingController.swift` | Recording lifecycle, file naming, quit-safety.                    |
| `HoldPicker/Recording/RecordingHUD.swift`   | Floating stop pill: timer, saving, saved (reveal in Finder).           |
| `HoldPicker/Recording/RecordingFrameWindow.swift` | Dashed outline around the recorded region.                       |
| `HoldPicker/Capture/Clipboard.swift`        | Writes PNG + TIFF to the general pasteboard.                           |
| `HoldPicker/Overlay/*`                      | Selection window and layer-based view.                                 |
| `HoldPicker/Support/Preferences.swift`      | `UserDefaults`-backed settings.                                        |
| `HoldPicker/Support/Permissions.swift`      | Accessibility and Screen Recording checks and deep links.              |
| `HoldPicker/Support/ScreenGeometry.swift`   | CG ↔ Cocoa conversions, display lookup.                                |
| `HoldPicker/Support/Log.swift`              | `os.Logger` categories.                                                |

## Extending

- **Save to file**: add a sink next to `Clipboard.write` and a preference for
  the destination. `commitSelection` in the controller is the only call site.
- **Multi-display selections**: show one overlay per screen and capture with
  one `SCContentFilter` per display, then stitch. The recognizer needs no change.
- **Window capture**: on `beginSelection`, query `SCShareableContent.windows`
  under the pointer and snap the rectangle to that window's frame.
