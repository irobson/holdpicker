#!/usr/bin/env bash
#
# Builds HoldPicker with SwiftPM and wraps the binary in a minimal .app bundle.
#
# Usage:
#   scripts/bundle.sh                 # release build -> build/HoldPicker.app
#   CONFIG=debug scripts/bundle.sh    # debug build
#   SIGN_IDENTITY="Apple Development: ..." scripts/bundle.sh
#   UNIVERSAL=1 scripts/bundle.sh     # arm64 + x86_64 (needs full Xcode)
#
# Why a bundle? macOS privacy permissions (Accessibility, Screen Recording) are
# granted per app identity. A bare binary works, but a bundle with a stable
# bundle identifier makes the permission grants survive rebuilds.
#
# SIGN_IDENTITY defaults to "-" (ad-hoc). Ad-hoc signatures change on every
# build, so macOS may ask for permissions again after rebuilding. Use a real
# signing identity from your keychain for a stable grant.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="HoldPicker"
CONFIG="${CONFIG:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
ARCH_FLAGS=()
if [[ -n "${UNIVERSAL:-}" ]]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi
OUT_DIR="$ROOT/build"
APP="$OUT_DIR/$APP_NAME.app"

echo "▸ Building ($CONFIG)…"
# `${arr[@]+...}` keeps bash 3.2 happy under `set -u` when the array is empty.
swift build -c "$CONFIG" --package-path "$ROOT" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c "$CONFIG" --package-path "$ROOT" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

echo "▸ Assembling $APP"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "▸ Signing with identity: $SIGN_IDENTITY"
codesign --force --sign "$SIGN_IDENTITY" --timestamp=none "$APP"

echo "✓ Done: $APP"
