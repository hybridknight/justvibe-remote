# Trust and local data

JustVibe Remote was authored as a new project. No source, bridge, assets, or binaries were copied from MiVibe-Remote. Hardware identity and interface descriptors were observed through the operating system, and the implementation uses documented platform interfaces.

## What the app does

- Reads button events for the selected hardware identity after Start.
- Saves button usage codes, mappings, shortcut text, the selected target application path, and per-device microphone IDs/names/safeguard preferences.
- Activates the chosen Codex application and sends configured keyboard events.
- On macOS, optionally uses the system `hidutil` executable with numeric device matching to replace mapped buttons' native actions. Original owned mappings are journaled first and restored when possible.

## What the app does not do

- No speech recognition, transcription, audio upload, continuous background audio capture, or audio driver installation. The explicit Microphone test is the recording exception described below.
- No API key, login, network listener, HTTP client, analytics endpoint, or updater.
- No shell actions, arbitrary command bindings, scripts inside plugin manifests, vendor DLLs, or downloaded helper executables.
- Plugin API v1 loads JSON data only. App plugins can still define keystrokes with effects in the target app; use plugins you trust. Displayed author names are not authenticated publisher identities.
- Normal operation does not log keyboard events. An explicitly launched, bounded dictation-button diagnostic records only the selected remote microphone button’s down/up state and timing; it does not record speech or other keys. Windows receives Raw Input packets from the OS and discards unmatched device identities before decoding button content. macOS registers a device-specific HID match.

Codex itself may transmit microphone audio as part of its own dictation service. JustVibe Remote does not change that service's privacy behavior.

## Optional microphone test

Only clicking **Start 5-second test** opens an audio input and, on macOS, requests Microphone permission. The UI binds capture to the selected device, displays a meter, and retains at most five seconds of mono PCM in memory for playback. It never writes an audio file or uploads the preview. Stop ends capture; Close, Delete clip, changing inputs, or Refresh discards the preview. Playback uses the normal system output. Native audio APIs and runtime/OS buffers may make temporary internal copies; this is not a secure-memory-erasure promise.

The test window pauses JustVibe Remote’s mapped actions. It does not intercept Windows native input. Selecting a saved microphone is independent of choosing app plugins. macOS can explicitly change the system default input when the user clicks the corresponding button; this is a global OS input choice and is not silently restored on close. Windows default changes happen through the user's Sound settings. The safeguard checks selected-device availability and system defaults, not another app's internal audio stream or input override. Nothing in this feature inspects Codex's private settings or routes a preview into Codex.

## Local files

macOS:

- `~/Library/Application Support/JustVibeRemote/settings.json`
- `~/Library/Application Support/JustVibeRemote/key-mapping-leases.json`
- `~/Library/Application Support/JustVibeRemote/cursor-speed-leases.json`

Windows:

- `%APPDATA%/JustVibeRemote/settings.json`

Community plugins live in a `plugins` subdirectory alongside each platform's settings file. Only selected device/app plugins activate after Start. Reload first stops the current session. See [plugin trust boundaries](PLUGINS.md#trust-boundary).

A corrupt settings file is preserved and reported rather than silently overwritten. Device-mapping journals survive unplugging or crashes so restoration can be retried.

## Permissions and builds

macOS requires Input Monitoring to receive the selected receiver's HID events and Accessibility to send shortcuts. The optional microphone test separately needs Microphone permission, requested only when starting a test. The app asks when Start or Permissions is chosen, not just because the app opens. The OS grants Input Monitoring to the application identity; a diagnostic process's permission does not grant permission to JustVibe Remote.

Windows runs as the current user. It does not request administrator access. Windows can reject synthetic input to a more privileged target, and JustVibe Remote reports that failure.

Source builds use Apple's SDK/toolchain or Microsoft's .NET SDK. Self-contained Windows packaging downloads Microsoft's runtime packs. The app has no third-party NuGet or Swift package references. Build-tool behavior is separate from app behavior.

The delivered builds are development artifacts. They have not been security audited, Apple-notarized, or signed with a commercial Windows publisher certificate. Automated tests and compilation do not establish that a physical remote's microphone or proprietary protocol works.

## Connection recovery

The optional Connection check reads only macOS permission state and matched USB receiver metadata, and may briefly open/close a non-seizing HID manager without registering input callbacks. Its Reset buttons invoke the system `tccutil` for this app’s bundle identifier and only the chosen ListenEvent or Accessibility service, after stopping the active session. Reset never grants access; macOS requires user approval again. The diagnostic CLI exits before creating the controller and never starts audio or shortcut output. A restart closes the active adapter and releases held output before opening a fresh app process.

Changed ad-hoc signatures can invalidate existing TCC approvals. The build requires a persistent signing identity, with normal certificate-based signature requirements and no silent ad-hoc fallback. The optional explicit local-signing setup creates a dedicated user keychain and user-only certificate trust constrained to code signing. It never adds system-wide or TLS trust, packages the private key, or manufactures a bundle-ID-only requirement. The non-extractable key, unlock credentials, and certificate live outside the checkout with owner-only directory/file permissions. An explicitly supplied Apple signing identity can be used instead. Successful device enumeration proves attachment, not that physical button learning or dictation has passed.

## Native cursor preferences

Optional cursor settings write only the selected receiver’s native tracking parameter. The original value is journaled before changes and restored when possible on reset, close of an unsaved preview, or quit. No exclusive pointer ownership or synthetic cursor movement is used. Physical pointing calibration and its saved reference model were removed; obsolete settings fields are ignored and omitted on the next save.
