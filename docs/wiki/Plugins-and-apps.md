# Plugins and apps

## Bundled plugins

| Plugin | Platforms | Controls |
| --- | --- | --- |
| [XING WEI 2.4G USB](https://github.com/hybridknight/justvibe-remote/blob/main/plugins/bundled/org.justviberemote.device.xingwei-usb/plugin.json) | macOS, Windows | Receiver `1915:1025`, visual button layout |
| [ChatGPT](https://github.com/hybridknight/justvibe-remote/blob/main/plugins/bundled/org.justviberemote.app.chatgpt/README.md) | macOS, Windows | Open app, dictation, Send, Backspace, Escape |
| [Antigravity](https://github.com/hybridknight/justvibe-remote/blob/main/plugins/bundled/org.justviberemote.app.antigravity/README.md) | macOS | Open app, toggle dictation, Send, Backspace, Escape |
| [Cursor](https://github.com/hybridknight/justvibe-remote/blob/main/plugins/bundled/org.justviberemote.app.cursor/README.md) | macOS | Open app, hold-to-talk dictation |

Platforms reflect the manifests. Confirm shortcuts in your app; see each plugin’s notes for setup and testing status. Standard USB and Bluetooth HID remotes can be supported through device plugins. Proprietary protocols and Bluetooth audio need separate verification.


## Add remotes and apps

On macOS, use **Add a new remote…** to identify a receiver. If no plugin matches, copy the generated agent prompt and supply a front-facing photo. In a remote’s **Apps** page, use **Add app…** or drop an application from Finder to create a local app profile.

To install a plugin, open **Plugins → Open plugin folder…**, copy its folder there, then click **Reload plugins**. Reload disconnects active sessions. Button mappings are saved per remote and app.

To launch an app from a remote button, open **Buttons**, select a button such as
**Power**, and choose **Action → Open app**. Check one or more apps and save the
Action. With multiple apps, each press opens the next checked app from top to
bottom, then wraps back to the first. Holding the button does not advance again.
A running app is brought to the front. Each remote button keeps its own cycle
position for the current session; restarting the app starts at the first app.
Use **Choose apps…** to change the selection. On macOS, drag rows to rearrange
the opening order, or select a row and use **Move up** / **Move down**. Windows asks you to locate each
app's `.exe` when its location is unknown. Link the physical button if needed.
The Action belongs to that remote's selected app profile;
**No specific app** provides shared controls under the existing routing rules.

To reuse a button’s action, select it in **Buttons** and click **Apply to all apps**.
This copies the action (including an Open app cycle and its order) to installed
app profiles on that remote, replacing that button’s previous actions. It also
updates **No specific app** when the action is supported, so shared controls work
in other apps such as Chrome. Other buttons, learned signals, app locations, and
per-app dictation shortcuts stay unchanged. Incompatible profiles are listed in
the status message; app dictation is never copied into shared controls. This is a
one-time copy; later edits and newly added app profiles keep their own settings.

Create plugins with the [agent authoring guide](https://github.com/hybridknight/justvibe-remote/blob/main/docs/PLUGIN-AUTHORING.md), [API reference](https://github.com/hybridknight/justvibe-remote/blob/main/docs/PLUGINS.md), and [device or app starters](https://github.com/hybridknight/justvibe-remote/blob/main/plugins/examples/README.md). For photo-based layouts, see [image-to-plugin](https://github.com/hybridknight/justvibe-remote/blob/main/docs/IMAGE-TO-PLUGIN.md). Plugins contain declarative JSON and documentation; the host does not execute plugin scripts or native libraries.

Validate with the .NET 10 SDK:

```sh
dotnet run --project windows/JustVibeRemote.PluginTool -- validate /absolute/path/to/plugin-folder
```
