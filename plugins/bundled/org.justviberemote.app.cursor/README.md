# Cursor app plugin

ID: `org.justviberemote.app.cursor` · Version 1.0.2 · macOS · schema/API 3/3.

Bundled with JustVibe Remote. Targets Cursor, locally inspected at version 3.27.22 with bundle ID `com.todesktop.230313mzl4w4u92`. Windows is not declared. Provides Focus and Dictate; other optional actions are omitted because their behavior was not verified.

## Setup

Select **Cursor** in your remote's Apps page. Link a remote control and assign Dictation. In **Voice & microphone**, confirm **CTRL+M** (Control+M, not Command+M) against Cursor's actual settings and save. Choose toggle activation to press once to start and again to stop. With hold activation, pressing starts and releasing stops. Cursor receives one complete Control+M tap to start and another complete tap to stop. The shortcut is never held for the recording. This does not change Cursor’s keyboard bindings. Select the microphone inside Cursor; this plugin does not route audio.

The user explicitly selected tap-to-start / tap-to-stop Control+M behavior. Keep Cursor’s own dictation and keyboard settings. Different Cursor windows and versions can have different defaults, so confirm the actual keyboard behavior in the window you use. Start with dictation off and use the remote for both transitions; the host cannot query Cursor’s recording state. Avoid mixing manual toggles with an active remote session.

The host owns focus checks and shortcut cleanup. Verify focus loss, profile changes, Stop, disconnect, and timeout with the actual app and remote before relying on them.

No manual community installation is needed in builds containing this plugin. Reload plugins or restart after updating the app, then configure Cursor. If an earlier community Cursor plugin is installed, move it outside the user plugin directory and Reload before configuring the bundled profile. Both packages target Cursor, causing ambiguous Follow active app routing. Saved bindings use different IDs and are not migrated automatically; the old source package can remain outside the installed plugin directory as a backup.

Validation and live-test status are recorded in tests/ACCEPTANCE.md. No separate plugin license has been selected.
