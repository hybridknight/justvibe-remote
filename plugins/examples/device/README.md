# Device plugin starter

This folder is an agent-ready starting point, not a verified device integration. The sample `1234:5678` hardware identity and other example metadata are placeholders.

Copy the entire folder to a separate plugin project. Ask your coding agent to read `AGENTS.md` and `PLUGIN-GUIDE.md`, then author the plugin using observed device evidence. Keep JustVibe Remote's core source unchanged. The included schema is a reference snapshot, not something to loosen to pass validation.

Validate from a known JustVibe Remote checkout with:

```sh
dotnet run --project /absolute/path/to/JustVibeRemote/windows/JustVibeRemote.PluginTool -- validate /absolute/path/to/your-plugin
```

Record actual results in `tests/ACCEPTANCE.md`. Replace this README with the remote's identity, evidence, supported platforms, installation, microphone behavior, test status, and limitations. Choose your package license or state that it is not yet selected.

Install the finished package in the user's external plugin directory, then Reload and select it in JustVibe Remote. Keep its source outside the host checkout so core updates do not require merging your integration.

## Use a remote photo

Attach a front-face photo or packaging image and ask your agent to trace it into the schema/API 2/2 `device.layout`. This starter's generic drawing is a placeholder. Use stable IDs, label uncertain symbols, and keep unverified `usage` fields absent. A photo does not supply VID/PID, electrical reports, or microphone transport. Read PLUGIN-GUIDE.md for the full portable photo-to-layout workflow. You should not need to edit the core renderer for supported visual layouts.
