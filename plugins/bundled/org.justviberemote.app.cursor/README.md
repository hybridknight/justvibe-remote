# Cursor app plugin

ID: `org.justviberemote.app.cursor` · Version 1.0.3 · macOS · schema/API 1/1.

Bundled with JustVibe Remote. Targets Cursor, locally inspected at version 3.27.22 with bundle ID `com.todesktop.230313mzl4w4u92`. Provides Focus and Dictate. Windows is not declared.

## Setup

Select **Cursor** in the remote’s Apps page. Link the microphone button and assign Dictation. Confirm **CTRL+M** (Control+M) in the dictation shortcut settings. For receivers that send a short mic pulse even when the physical button is held, turn **Press once to start, again to stop** on and save: the first press holds Control+M, and the next press releases it. The XING WEI receiver was observed to send approximately 120 ms pulses during physical holds, so this is the user-selected setup for that receiver. For a button verified to report a continuous hold, turn this option off to hold the remote button while speaking and release it to stop. Existing profiles retain their activation preference until changed and saved.

Cursor’s installed Control+M command is **Hold to Talk**. Version 1.0.3 restores held-shortcut output. On 2026-10-30, the user chose to toggle this held shortcut between mic presses after a timing check showed the receiver sends short pulses during physical holds. Version 1.0.2 sent quick start/stop taps, which released Hold to Talk immediately. Cursor’s own keyboard bindings remain unchanged. Choose the microphone inside Cursor; this plugin does not route audio.

The host owns focus checks and key cleanup. A focus change, Stop, disconnect, or timeout releases the held shortcut. Verify these behaviors with the actual app and remote. If a community Cursor plugin is also installed, move it outside the user plugin directory and Reload to avoid ambiguous routing.

No separate installation is needed in builds containing this bundled plugin. Reload plugins or restart after updating the app, then update the saved Cursor activation preference as described above. Validation and live-test status are recorded in tests/ACCEPTANCE.md. License: undecided.
