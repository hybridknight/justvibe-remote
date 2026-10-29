# App plugin starter

This folder is an agent-ready starting point, not a verified application integration. Example Editor and its identities/shortcuts are placeholders. Dictation is intentionally omitted; add it only if a held shortcut is supported and verified.

Copy the entire folder to a separate plugin project. Ask your coding agent to read `AGENTS.md` and `PLUGIN-GUIDE.md`, then author the plugin using verified app identities and shortcut behavior. Keep JustVibe Remote's core source unchanged.

Validate from a known JustVibe Remote checkout with:

```sh
dotnet run --project /absolute/path/to/JustVibeRemote/windows/JustVibeRemote.PluginTool -- validate /absolute/path/to/your-plugin
```

Record actual results in `tests/ACCEPTANCE.md`. Replace this README with the app/version, identities, actions, installation, tested platforms, and limitations. Choose your package license or state that it is not yet selected.

Install the finished package in the user's external plugin directory, then Reload and select it in JustVibe Remote. Keep its source outside the host checkout so core updates do not require merging your integration.
