# Cursor acceptance record

- Plugin: org.justviberemote.app.cursor 1.0.0; author metadata: JustVibe Remote.
- Declared platform: macOS; schema/API 3/3, shortcuts adapter.
- App identity: Cursor 3.27.22, com.todesktop.230313mzl4w4u92, read from local Info.plist on 2026-10-29.
- Shortcut evidence: user supplied CTRL+M and confirmed press-to-start / press-to-stop.
- Official validator: PASS on 2026-10-29 (exit 0).
  Command: `dotnet run --project windows/JustVibeRemote.PluginTool -- validate plugins/bundled/org.justviberemote.app.cursor`
  Result: `Valid API v3 app plugin: org.justviberemote.app.cursor 1.0.0 (macos)`. A CSSM_ModuleLoad diagnostic preceded the successful result.
- Automated checks: PASS on 2026-10-29. `./scripts/test-macos.sh`: 261 core checks and 130 remote-session checks. Includes bundled Cursor discovery, target identity, toggle Control+M defaults, and explicit shortcut confirmation. `dotnet run --project windows/JustVibeRemote.Tests/JustVibeRemote.Tests.csproj -- .`: 183 Windows core checks; this is not a Windows runtime test. macOS session checks emitted NSWorkspace notification diagnostics but exited 0.
- Runtime source changes: none; bundled package, tests, and documentation only.
- License: undecided.

## Live checks — all untested

- Bundled package appears after app update/reload; Focus finds Cursor.
- User confirms the shortcut against Cursor settings; remote starts and stops dictation.
- Stop, disconnect, timeout, reload, and focus loss clean up the session without targeting unrelated apps.
- Configure the same remote button differently in Cursor and a second profile; test both and native fallback in an unsupported app.
- Change focus during dictation and delayed starts; verify cleanup/cancellation without changing the editor profile or writing settings on every focus change.
- Overlapping Cursor targets stay inactive until uniquely configured; remove the earlier community copy from the installed plugin root before testing bundled routing.
- Verify microphone choice inside Cursor and actual remote behavior. No recording or key injection was performed by automated checks.

Windows and hardware support are not claimed by static validation.
