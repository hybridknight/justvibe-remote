# Cursor acceptance record

- Plugin: org.justviberemote.app.cursor 1.0.2; macOS, schema/API 3/3.
- Identity: Cursor 3.27.22, com.todesktop.230313mzl4w4u92, locally inspected on 2026-10-29.
- Required behavior: the user explicitly requested Control+M taps for dictation, not a held chord. Version 1.0.2 uses toggle-shortcut: one complete tap on start, another on stop.
- Cursor keyboard settings remain unchanged. No custom glass.dictate override or separate dictation app is installed by this change.
- Source-code Hold to Talk defaults from one Cursor window are not evidence of the user’s desired tap behavior. Verify the actual target window separately.
- Official semantic validation: PASS (exit 0). `dotnet run --project windows/JustVibeRemote.PluginTool -- validate /Users/hybridknight/workspace/justvibe-remote/plugins/bundled/org.justviberemote.app.cursor` returned `Valid API v3 app plugin: org.justviberemote.app.cursor 1.0.2 (macos)`. A CSSM_ModuleLoad diagnostic preceded success.
- Automated checks: PASS (exit 0). `scripts/test-macos.sh`: 294 core checks and 138 remote-session checks, including the Cursor toggle-shortcut declaration and toggle lease start/stop/cleanup checks. Session tests emitted a nonfatal NSWorkspace notification diagnostic. These checks do not inject keys or record audio.
- Earlier live success used a temporary custom Cursor toggle binding; it does not verify version 1.0.2 with unmodified Cursor keybindings.
- License: undecided.

## Live checks — pending for 1.0.2

- Confirm Control+M starts/stops native dictation from the keyboard in the intended Cursor window, then verify the remote.
- Remote toggle activation: first press sends one tap; second press sends another. No Control+M chord stays held between presses.
- Stop, disconnect, timeout, reload, and focus loss send cleanup to the original target without toggling voice in unrelated apps.
- Switch between Cursor, another configured app profile, and an unsupported app. Change focus during a delayed start and while recording; confirm cleanup without altering the editor profile.
- Overlapping target matches remain inactive until uniquely configured.
- Verify microphone choice and speech recognition inside Cursor. No automated test should start a recording or inject keys.

Windows and physical-device support are not claimed by static validation.
