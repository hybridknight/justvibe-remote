# Architecture

JustVibe Remote has two small native frontends and a shared plugin contract. There are no embedded browser runtimes and no app-level package dependencies.

```text
Selected remote receiver
    → OS HID adapter
    → normalized Usage(page, code) + press/release
    → configured profile for the foreground app (or selected-app mode)
    → learned button binding
    → app focus check / shortcut action

Receiver USB microphone
    → operating system audio device
    → Codex microphone selection
```

## Boundaries

- `plugins/bundled/`: independently loadable device and app manifests.
- `plugins/examples/`: creator templates; not loaded by the app.
- `plugins/plugin.schema.json`: structural manifest contract.
- `macos/Sources/Plugins.swift` and `windows/JustVibeRemote.Core/Plugins.cs`: validation, discovery, conflicts, and plugin selection.
- `macos/Sources/Model.swift`: configuration, normalized usages, button actions, voice state.
- `macos/Sources/NativeIO.swift`: Apple HID callbacks and Codex keyboard events.
- `macos/Sources/MappingLease.swift`: scoped native-action replacement and persistent restoration journal.
- `macos/Sources/Controller.swift`: learning, lifecycle, foreground checks, dictation transitions.
- `macos/Sources/main.swift`: AppKit settings window.
- `windows/JustVibeRemote.Core/`: portable configuration, identity filtering, report decoding, voice state.
- `windows/JustVibeRemote.App/`: WinForms settings window, Windows Raw Input, checked SendInput, focus/lifecycle controls.
- Platform tests run against synthetic usages and reports, not live user typing or recorded audio.

The app listens on launch only after the user enables automatic reconnect (and, on macOS, grants permissions). Connect remote enables the selected receiver adapter. Changing settings releases the active shortcut and restarts the adapter if it was running. Button learning saves only the normalized button usage, never text or raw audio.

The output boundary is generic: app identity and shortcuts come from the selected app plugin. Codex is bundled, not implemented as a special native output class. The selected application path remains a user override. See [the plugin contract](PLUGINS.md) for installation, lifecycle, and extension boundaries.

## Voice contract

The output is a held keyboard shortcut, not an audio stream. The user matches it to Codex's hold-to-dictate shortcut. Toggle mode translates separate physical presses into a held shortcut; hold mode follows physical edges. The active shortcut is retained until its release succeeds.

Future target adapters can implement different shortcut semantics. Future audio adapters should remain separate from key adapters; a remote's microphone transport cannot be inferred from its button protocol.

## Current implementation limits

- The bundled device plugin covers the `1915:1025` XING WEI variant; additional supported HID identities and report layouts can be supplied by community device plugins.
- Visual API 2 device plugins define their own controls and geometry. Legacy API 1 devices use a generic layout. Custom protocols still require a host adapter.
- macOS learns standard HID button elements and ignores mouse movement and vendor data.
- Windows normalizes common keyboard keys and descriptor-specific 16-bit consumer reports. Unsupported keys or report families need another decoder.
- Windows custom commands are additive, not full device-specific native-event replacement.
- There is no proprietary Bluetooth microphone decoder, automatic microphone routing, updater, account system, startup agent, or background service.
- The window currently owns the app lifecycle. Closing it stops the app.

## Visual configuration

`RemoteLayout.swift` and `RemoteLayout.cs` validate common geometry and migrate bindings by stable control ID. Native `RemoteCanvas` views render the same declarative layout with selectable, accessible button controls. The inspector presents one control at a time, with learning status and app actions; voice settings are contextual and signal details are under Advanced.

The XING WEI front face is traced from the supplied packaging photo, with uncertain symbols called out and no signal usages invented. API 2 visual device manifests remain independent of core updates. See IMAGE-TO-PLUGIN.md.

## Active application profiles

`AppRouting.swift` and `AppRouting.cs` resolve foreground identities without changing the editor selection. Configuration stores `followActiveApp` (default false for backward compatibility) and `appMappings`, keyed by device plugin ID + `|` + app plugin ID. A snapshot contains bindings, dictation shortcut and confirmation, voice mode, target-path override, and test completion. The current editor profile is authoritative; previous `bindingSets` remain readable as legacy profiles with unconfirmed dictation shortcuts.

Only the selected or previously configured plugin profiles participate. Explicit app paths take precedence over bundle IDs, then display/process names. An explicit path never falls back to names. The highest match must be unique; missing identities and ties produce no custom route. Windows paths and process names match without case sensitivity. These identities are targeting rules, not publisher authentication.

The controllers check the foreground before handling each remote edge and poll every 250 ms; macOS also observes app activation. App-instance changes cancel pending starts and release held output before applying the next route. Delayed dictation starts recheck the route and foreground. On macOS the device mapping lease is recalculated for the active profile and restored for unmatched apps or learning. Native-action restoration follows the foreground notification/check and is not an atomic OS-wide app switch. Windows native input remains additive as documented.

Editor changes restart a running adapter as before. Changing apps automatically does not write settings or restart HID input. Learning stays attached to the editor profile, and configuring a fresh profile reuses matching learned physical signals from the same device. Updating a plugin cannot enable an unsupported saved action.

## Explicit microphone testing and input safeguards

`AudioPreview.swift` / `AudioPreview.cs` provide a bounded PCM16 mono preview and pure microphone-policy checks. `MicrophoneAudio` enumerates native inputs with stable IDs; it captures only when the user starts a local test. macOS uses an AudioQueue recording session bound to the selected CoreAudio UID at the device’s nominal sample rate. It verifies the UID before starting and in input callbacks, captures mono PCM16 into bounded memory, and disposes the queue synchronously on Stop. The meter uses dB scaling and reports received buffers/samples separately from signal level. Windows uses waveIn with an explicit enumerated device index mapped to its opaque endpoint ID via DRV_QUERYFUNCTIONINSTANCEID, rechecked after opening. Its window-message callback owns four prepared buffers; reset/unprepare/close precede freeing them. No WAVE_MAPPER/default-input fallback is used for testing. Disconnects/source changes stop or invalidate capture. The mono preview is capped at five seconds; delayed UI handling cannot grow it indefinitely.

macOS sets the default input only from the explicit UI action. Windows uses IMMDeviceEnumerator to verify capture endpoints for console, multimedia, and communications roles; it uses the Windows Settings UI for default changes. Per-device `microphones` settings are backward-compatible and optional. When enabled, policy checks run before starting dictation, again after delayed focus activation, and while the shortcut is held. They do not prove the target application's input selection. The host does not route preview audio, transcribe it, or install a virtual audio device. Microphone-test windows stop dictation and suspend mapped actions until close.

Native references: [CoreAudio default device properties](https://developer.apple.com/documentation/coreaudio/audioobjectsetpropertydata(_:_:_:_:_:_:)), [audio unit current device](https://developer.apple.com/documentation/audiotoolbox/kaudiooutputunitproperty_currentdevice), [Windows endpoint IDs](https://learn.microsoft.com/en-us/windows/win32/coreaudio/endpoint-id-strings), and [device roles for legacy multimedia](https://learn.microsoft.com/en-us/windows/win32/coreaudio/device-roles-for-legacy-windows-multimedia-applications). These APIs establish device identity/default checks; they do not expose Codex's private input state.

## Single normal session on macOS

`SingleInstanceLock` takes a per-user nonblocking exclusive lock on the settings directory's session file using `O_EXLOCK`. Close-on-exec prevents restart helpers inheriting session ownership. A duplicate normal launch activates the owning PID and exits before constructing a controller. Read-only diagnostic/preview modes bypass ownership and keep activation prohibited. Restart uses a bounded helper that waits for the old PID to exit before reopening through Launch Services; it does not create an overlapping normal instance.

## Native cursor controls (macOS)

`CursorSettings.swift`, `CursorSpeed.swift`, and `CursorSetup.swift` retain per-receiver native tracking preferences, bounded preview/save/reset, and restoration leases. The physical reference capture, coordinate mapping, exclusive pointer ownership, synthetic cursor output, and special companion-keyboard listener have been removed. The standard remote listener again observes all matched receiver interfaces without seizing them. Unknown old calibration fields are ignored by the settings decoder and are not encoded again.
