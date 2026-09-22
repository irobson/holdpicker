# Architecture

HoldShot is small on purpose. This document explains the parts that are not
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
                      beginSelection ─► SelectionOverlayWindow.show()
                      updateSelection ─► overlay.setSelection(cgRect:)
                      commitSelection ─► ScreenCapturer.capture(...) ─► Clipboard.write(...)
                      cancelSelection ─► overlay.dismiss()
```

Everything runs on the main actor. The tap's run loop source is attached to the
main run loop, the hold timer is a `DispatchWorkItem` on the main queue, and
AppKit is main-thread only anyway. There is no shared mutable state across threads.

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

The recognizer itself (`HoldShotCore/HoldGestureRecognizer.swift`) is a pure
state machine. It owns no timer and touches no I/O; it just returns what should
happen. That is what makes it unit-testable without a window server.

```
 idle ──down──► pending ──timeout──► selecting ──up──► idle
                  │  │                   │
                  │  └──up/move────► (replay) ──► passthrough ──up──► idle
                  │
                  └──(modifier missing)──► pass, stay idle
```

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

The overlay window is passed to ScreenCaptureKit as an excluded window, so the
capture never contains the dimming or the frame even though the flash animation
is still on screen while the capture runs.

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
| `HoldShotCore/HoldGestureRecognizer.swift`| Gesture state machine. Pure, tested.                                   |
| `HoldShotCore/Geometry.swift`             | Rect normalization and clamping helpers.                               |
| `HoldShot/App/HoldShotApp.swift`          | `@main` entry; sets accessory activation policy.                       |
| `HoldShot/App/AppDelegate.swift`          | Wires controller and menu; handles termination.                        |
| `HoldShot/App/StatusBarController.swift`  | Menu bar item, all user-facing settings.                               |
| `HoldShot/Capture/EventTap.swift`         | `CGEvent` tap wrapper; re-enables itself after timeouts.               |
| `HoldShot/Capture/CGEvent+Replay.swift`   | Synthetic marker and HID-level replay.                                 |
| `HoldShot/Capture/CaptureController.swift`| Orchestrates tap, recognizer, timer, overlay, capture, clipboard.      |
| `HoldShot/Capture/ScreenCapturer.swift`   | ScreenCaptureKit region capture.                                       |
| `HoldShot/Capture/Clipboard.swift`        | Writes PNG + TIFF to the general pasteboard.                           |
| `HoldShot/Overlay/*`                      | Selection window and layer-based view.                                 |
| `HoldShot/Support/Preferences.swift`      | `UserDefaults`-backed settings.                                        |
| `HoldShot/Support/Permissions.swift`      | Accessibility and Screen Recording checks and deep links.              |
| `HoldShot/Support/ScreenGeometry.swift`   | CG ↔ Cocoa conversions, display lookup.                                |
| `HoldShot/Support/Log.swift`              | `os.Logger` categories.                                                |

## Extending

- **Save to file**: add a sink next to `Clipboard.write` and a preference for
  the destination. `commitSelection` in the controller is the only call site.
- **Multi-display selections**: show one overlay per screen and capture with
  one `SCContentFilter` per display, then stitch. The recognizer needs no change.
- **Window capture**: on `beginSelection`, query `SCShareableContent.windows`
  under the pointer and snap the rectangle to that window's frame.
