# ChatGPT app plugin

Plugin ID: `org.justviberemote.app.chatgpt` · Version 1.1.2.

The plugin folder and ID now use ChatGPT. JustVibe Remote migrates the previous app-plugin ID and saved per-app mapping keys when loading settings. Existing controls, voice preferences, and per-remote app selections are preserved; existing ChatGPT entries take precedence if both namespaces were saved.

The macOS application identity remains `com.openai.codex`, verified from the installed ChatGPT 26.1023.50603. Both ChatGPT and legacy Codex display/process names are recognized. The application's bundle identity is independent of the JustVibe Remote plugin namespace.

Actions: focus, dictation (Control+Shift+M on macOS and Windows), Send, Backspace, and Escape. Version 1.1.2 changes the suggested dictation shortcut to the user-requested `CTRL+SHIFT+M`. In ChatGPT’s **Settings → Keyboard Shortcuts**, set the dictation command to **Control+Shift+M**, then enter and confirm the same shortcut in JustVibe Remote. Existing saved shortcut overrides are preserved; select `CTRL+SHIFT+M` in **Voice & microphone** and save to update an existing profile. Live dictation and Windows behavior have not been retested for this shortcut change.

Static validation (2026-10-30): the existing built official PluginTool passed with `Valid API v1 app plugin: org.justviberemote.app.chatgpt 1.1.2 (macos, windows)`. The source-run validation stalled during build/restore; validation used the existing tool binary.
