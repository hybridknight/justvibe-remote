# Antigravity app plugin

ID: `org.justviberemote.app.antigravity` · Version 1.0.0 · macOS · schema/API 3/3.

Targets the Antigravity desktop app (`com.google.antigravity`), inspected locally at version 2.27.0. Antigravity IDE (`com.google.antigravity-ide`) and the CLI are separate targets. Windows is not declared by this plugin.

## Microphone button → Control+M

Select **Antigravity** above Buttons. The bundled receiver layout’s microphone button is assigned to **Dictation**, and a learned microphone signal is reused from the current remote. In **Voice & mic**, confirm that the shortcut is **CTRL+M** and save. Choose/test the receiver’s microphone and select the same input in Antigravity if needed.

With the default remote activation mode, press the remote’s microphone button once to start dictation, then again to stop. If you choose hold activation in JustVibe Remote, pressing starts and releasing stops. Antigravity always receives two separate Control+M taps rather than a held key.

The host retains the original process identity for the stop tap. It sends cleanup to that process on stop, focus loss, profile changes, receiver disconnect, microphone safeguard failure, timeout, or quit. Failed key-up events remain retryable without posting an extra toggle. No other app is focused to stop dictation.

Start with Antigravity dictation off and use the remote for both transitions. JustVibe Remote cannot read Antigravity’s internal recording state or verify that an OS-posted shortcut changed it. Avoid mixing manual microphone toggles with an active remote session.

Also provides Open app, Return, Backspace, and Escape. Held-shortcut plugins continue to use API 1; older hosts reject this API 3 manifest.

Source: [Google Antigravity voice transcription](https://antigravity.google/docs/features#voice-transcription). The shortcut was also supplied and its toggle behavior confirmed by the user.

Official validation and automated transition tests passed. Live key injection, microphone recording, and recognition inside Antigravity have not been tested for this change. No separate plugin license has been selected.
