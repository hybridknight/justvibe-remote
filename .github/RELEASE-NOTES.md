## Downloads

- **macOS ARM64:** macOS 13 or later on Apple Silicon. Extract the archive and move `JustVibe Remote.app` to Applications.
- **Windows win-x64 / win-arm64:** choose the archive matching your PC. Extract the entire archive and keep its files together, then open `JustVibeRemote.exe`. The .NET runtime is included.
- `SHA256SUMS.txt` contains the package checksums.

## Signing and testing

The macOS package is ad-hoc signed and is not Apple-notarized. Windows packages are not Authenticode-signed. These packages may be blocked or flagged by operating-system security checks.

Automated checks cover core behavior, session handling, plugin validation, and native Windows UI previews. They do not verify physical receivers, live dictation, microphone selection in another app, or real audio capture. Windows ARM64 is cross-built; it is not run on ARM64 hardware by this workflow. Review the repository's platform support and live-test notes before publishing this draft.

Dictation runs through the target app or optional macOS Dictation. JustVibe Remote does not upload audio.
