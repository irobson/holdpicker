#!/usr/bin/env bash
#
# Runs `swift test`, working around a Command Line Tools quirk: the Swift
# Testing runtime ships with the CLT but is not on the default search or
# rpath, so `swift test` fails with "no such module 'Testing'". With a full
# Xcode install none of this is needed and the flags are skipped.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEV_DIR="$(xcode-select -p)"
EXTRA_FLAGS=()

if [[ "$DEV_DIR" == *CommandLineTools* ]]; then
    FRAMEWORKS="$DEV_DIR/Library/Developer/Frameworks"
    INTEROP_LIB="$DEV_DIR/Library/Developer/usr/lib"
    EXTRA_FLAGS=(
        -Xswiftc -F -Xswiftc "$FRAMEWORKS"
        -Xlinker -F -Xlinker "$FRAMEWORKS"
        -Xlinker -rpath -Xlinker "$FRAMEWORKS"
        -Xlinker -rpath -Xlinker "$INTEROP_LIB"
    )
fi

# `${arr[@]+...}` keeps bash 3.2 (macOS /bin/bash) happy under `set -u` when the array is empty.
exec swift test --package-path "$ROOT" ${EXTRA_FLAGS[@]+"${EXTRA_FLAGS[@]}"} "$@"
