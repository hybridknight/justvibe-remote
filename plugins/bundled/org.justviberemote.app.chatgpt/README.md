# ChatGPT app plugin

Plugin ID: `org.justviberemote.app.chatgpt` · Version 1.1.1.

The plugin folder and ID now use ChatGPT. JustVibe Remote migrates the previous app-plugin ID and saved per-app mapping keys when loading settings. Existing controls, voice preferences, and per-remote app selections are preserved; existing ChatGPT entries take precedence if both namespaces were saved.

The macOS application identity remains `com.openai.codex`, verified from the installed ChatGPT 26.1023.50603. Both ChatGPT and legacy Codex display/process names are recognized. The application's bundle identity is independent of the JustVibe Remote plugin namespace.

Actions: focus, dictation (Control+M on macOS and Windows), Send, Backspace, and Escape. Version 1.1.1 changes the suggested dictation shortcut to the user-requested `CTRL+M`. Confirm the dictation shortcut in the app’s settings. Existing saved shortcut overrides are preserved; select `CTRL+M` in **Voice & microphone** and save to update an existing profile. Live dictation and Windows behavior have not been retested for this shortcut change.

Static validation (2026-10-29): official PluginTool passed with `Valid API v1 app plugin: org.justviberemote.app.chatgpt 1.1.1 (macos, windows)`.
