#!/bin/zsh
set -euo pipefail
ROOT="${0:A:h:h}"
mkdir -p "$ROOT/build/module-cache"
xcrun swiftc -swift-version 5 -module-cache-path "$ROOT/build/module-cache" \
  "$ROOT/macos/Sources/BackspaceRepeat.swift" "$ROOT/macos/Sources/VoiceStopTrigger.swift" "$ROOT/macos/Sources/CursorSettings.swift" "$ROOT/macos/Sources/SingleInstance.swift" "$ROOT/macos/Sources/ConnectionState.swift" "$ROOT/macos/Sources/AudioPreview.swift" "$ROOT/macos/Sources/AppRouting.swift" "$ROOT/macos/Sources/SetupFlow.swift" "$ROOT/macos/Sources/RemoteLayout.swift" "$ROOT/macos/Sources/Plugins.swift" "$ROOT/macos/Sources/Model.swift" "$ROOT/macos/Sources/NativeIO.swift" \
  "$ROOT/macos/Sources/MappingLease.swift" "$ROOT/macos/Tests/CoreTests.swift" \
  -o "$ROOT/build/JustVibeRemoteCoreTests"
"$ROOT/build/JustVibeRemoteCoreTests" "$ROOT"

"$ROOT/scripts/test-remote-sessions-macos.sh"
