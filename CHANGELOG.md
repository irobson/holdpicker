# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [0.1.0] - 2026-09-22

### Added
- Press-and-hold gesture to start a screenshot selection anywhere on screen.
- Hold-and-replay event handling so ordinary clicks and drags are unaffected.
- Dimmed overlay with live selection frame and size label.
- Region capture through ScreenCaptureKit at native (Retina) resolution.
- Result copied to the clipboard as PNG and TIFF; nothing is written to disk.
- Menu bar item with enable/disable, trigger modifier, hold duration, sound and launch-at-login options.
- Escape cancels an in-progress selection.
