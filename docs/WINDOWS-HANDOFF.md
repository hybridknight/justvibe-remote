# Continue Windows verification

The Windows implementation is ready for native review. Use this working tree or
the source archive supplied with the handoff; the changes have not been committed
or pushed. Do not use a fresh remote checkout without transferring these changes.

## Current work

- Shared Manrope headings, Inter controls, lavender sidebar, and consistent spacing.
- Remotes, Overview, Apps, Buttons, Microphone, Settings, Plugins, Help, and Button test.
- Resumable setup, local app registration, remote photos, independent receiver
  settings, shared Raw Input listener, and held-output ownership.
- **Action → Open app** now offers the existing app list. It saves the chosen app
  and executable location with the binding, independently of the profile being
  edited. Locate the `.exe` when no saved/running-app location is available.
  Legacy `focus` settings remain compatible; the plugin schema was not changed.
- Portable Windows checks: 228 passed on macOS. Mac core checks: 359 passed.
  Final build and receiver-session results are recorded in PLATFORM-PARITY.md.
- Windows was installed in a temporary VM, but **the app's native UI checks never
  ran**. The user stopped that work and the VM and installer were removed.

## First steps on Windows

Install the .NET 10 SDK, open this folder in Codex, and run from the repository root:

```powershell
dotnet run --project windows/JustVibeRemote.Tests -- .
./scripts/test-windows-ui.ps1
./scripts/build-windows.ps1 -Runtime win-x64
# Use -Runtime win-arm64 for a Windows ARM machine.
```

The UI script opens an isolated preview process with temporary settings. It creates
29 screenshots and `verification.json` in `build/windows-ui-verification`. It does
not start a receiver, send shortcuts, or capture audio. Check every screenshot,
including both page sizes and all setup stages/dialogs. Repeat at 100%, 150%, and
200% display scaling using separate `-OutputDirectory` folders; fix font fallback,
clipping, scroll reachability, and keyboard focus problems before claiming success.

Then launch `dist/windows-win-x64/JustVibeRemote.exe` (or the ARM64 build), check
navigation, app registration, saved profiles, photo selection/reset, plugin search,
setup continuation, and the new Open app picker. Assign Power to ChatGPT, test it
closed and already running, then test picker cancellation and target removal.
The new picker is a manual native check; it is not among the 29 automated previews.
Use disposable settings for experiments; preserve the
user's existing `%APPDATA%/JustVibeRemote` data.

## Hardware and remaining support boundaries

Follow the native acceptance checklist in [PLATFORM-PARITY.md](PLATFORM-PARITY.md).
Actual receiver behavior, cross-app held/delayed dictation, unplug/reconnect, and
microphone capture remain unverified. Never start recording as a test side effect;
the user must explicitly request or start live capture.

Windows Raw Input mappings remain additive. Per-receiver native cursor tuning and
API 3 toggle-shortcut plugins remain macOS-only. Windows voice typing uses Win+H;
Windows owns listening and stopping. Do not claim these are equivalent to the Mac
features or widen the plugin schema to conceal the differences.

Suggested Codex request:

> Read AGENTS.md, docs/WINDOWS-HANDOFF.md, and docs/PLATFORM-PARITY.md. Continue the
> existing Windows implementation. Run the portable and native UI checks, inspect
> every page and setup dialog, fix issues, and build for this machine. Keep updates
> brief. Preserve existing changes and settings. Report actual test evidence and
> remaining platform gaps; do not recreate a VM or start microphone recording.
