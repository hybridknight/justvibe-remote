# Acceptance evidence

- Installed app: Antigravity 2.27.0, `com.google.antigravity`.
- User-provided and Google-documented dictate shortcut: Control+M, press to start/stop.
- Official validator passed: `Valid API v3 app plugin: org.justviberemote.app.antigravity 1.0.0 (macos)`.
- Automated macOS checks passed: 254 core and 87 session checks; Windows shared core/validator checks: 183 passed.
- Tests cover exactly two taps, idempotent cleanup, failed start down/up, failed stop down/up and retries without duplicate toggles, strict API/platform validation, profile defaults, microphone action and learned-signal reuse.
- The new profile retains explicit shortcut confirmation.
- Live remote input, key injection, targeted background stop delivery, recording, recognition, and Windows runtime: unverified. No test side effects record audio or send keys.
