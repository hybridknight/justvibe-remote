#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
mkdir -p "$ROOT/build/module-cache"
SOURCES=("$ROOT"/macos/Sources/*.swift)
# Exercise the real session coordinator and controller without the app entry point.
xcrun swiftc -swift-version 5 -module-cache-path "$ROOT/build/module-cache" \
  "${(@)SOURCES:#*/main.swift}" "$ROOT/macos/Tests/RemoteSessionsTests.swift" \
  -o "$ROOT/build/RemoteSessionsTests"
"$ROOT/build/RemoteSessionsTests" "$ROOT"
