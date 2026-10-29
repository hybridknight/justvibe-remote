# Cursor acceptance record

- Plugin: org.justviberemote.app.cursor 1.0.3; macOS, schema/API 1/1.
- Identity: Cursor 3.27.22, com.todesktop.230313mzl4w4u92, locally inspected.
- Evidence (2026-10-30): installed Cursor command registers Control+M as Hold to Talk. The user confirms the physical keyboard shortcut works and explicitly chose to hold the remote button while talking.
- Version 1.0.3 uses hold-shortcut. Input-only live diagnostics observed three microphone signals lasting approximately 119–135 ms while the user reports holding the physical button for about three seconds. These signals end before the host’s 250 ms start delay when remote activation is hold.
- The user selected toggle activation for this receiver: first mic press holds Control+M, next press releases it. Cursor keyboard bindings are unchanged. A true held remote control can instead use hold activation.
- Official validation: PASS (exit 0), using the existing built official PluginTool: `Valid API v1 app plugin: org.justviberemote.app.cursor 1.0.3 (macos)`.
- Automated checks: PASS (exit 0), `scripts/test-macos.sh`: 347 core checks and 160 remote-session checks. A nonfatal NSWorkspace notification diagnostic was emitted. These checks do not inject keys or record audio.
- Live remote verification: pending. Physical-keyboard confirmation does not verify generated shortcut output.
- License: undecided.

## Live checks

- With the XING WEI pulse-only mic, press once in Cursor’s dictation input: Control+M stays held after the pulse ends; press again to release it.
- With a verified continuous-hold control, hold activation starts on press and stops on release.
- Change focus during a hold, stop, disconnect, and reload. Verify the original shortcut is released and no unrelated app receives a start command.
- Switch among Cursor, ChatGPT, Antigravity, and an unsupported app. Each configured app retains its own shortcut and activation preference.
- Verify the microphone and resulting text inside Cursor.

Windows and unperformed hardware tests are not claimed.
