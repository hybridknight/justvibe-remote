#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
# Explicit hardware test: briefly changes only the connected XING WEI pointer,
# restores its original value, and checks other pointer settings. Not run by builds.
mkdir -p "$ROOT/build/module-cache"
xcrun swiftc -swift-version 5 -module-cache-path "$ROOT/build/module-cache" \
  "$ROOT/macos/Sources/CursorSpeed.swift" "$ROOT/macos/Sources/VoiceStopTrigger.swift" "$ROOT/macos/Sources/CursorSettings.swift" "$ROOT/macos/Sources/SingleInstance.swift" "$ROOT/macos/Sources/ConnectionState.swift" "$ROOT/macos/Sources/AudioPreview.swift" "$ROOT/macos/Sources/AppRouting.swift" "$ROOT/macos/Sources/SetupFlow.swift" "$ROOT/macos/Sources/RemoteLayout.swift" "$ROOT/macos/Sources/Plugins.swift" "$ROOT/macos/Sources/Model.swift" "$ROOT/macos/Sources/NativeIO.swift" \
  "$ROOT/macos/Sources/MappingLease.swift" "$ROOT/macos/Tests/CursorNativeChecks.swift" \
  -o "$ROOT/build/JustVibeRemoteCursorNativeChecks"
"$ROOT/build/JustVibeRemoteCursorNativeChecks" "$ROOT"
