# JustVibe Remote

<img src="assets/branding/JustVibeRemote.svg" width="160" alt="JustVibe Remote: a silver remote with a microphone button over code bars" />

**Talk to your agent.**

Use a handheld remote to dictate, send prompts, navigate, and trigger shortcuts in your AI apps. Customize buttons for each app and add remote or app support through plugins.

Built for **macOS 13+ on Apple Silicon** and **Windows x64**. Voice input uses the target app’s dictation feature; compatibility depends on your hardware and plugins.

## Get started

After building:

- **macOS:** open `dist/JustVibe Remote.app`.
- **Windows:** copy the entire `dist/windows-win-x64` folder to your PC and open `JustVibeRemote.exe`. Keep the folder together; it includes the .NET runtime.

On macOS:

1. Open **Remotes**, choose **Set up remote**, and follow the welcome guide.
2. Connect your receiver and grant Input Monitoring and Accessibility when prompted.
3. Choose an app, select a button on the remote diagram, click **Learn this button**, then assign an action.
4. For voice, confirm the app’s dictation shortcut, choose and test the remote’s microphone, and select the same input inside the target app. Save your voice settings.
5. Switch to the target app and try the remote. **Follow active app** uses the configured controls for the app in front.

On macOS, **Buttons** tests and learns controls while JustVibe Remote is in front; switch to your target app to use assigned actions. If permissions appear enabled but connection fails, use **Connection check…** and restart after granting access.

Microphone testing starts only when you click **Start 5-second test**. A successful preview does not verify which microphone another app uses.

## Bundled plugins

| Plugin | Platforms | Controls |
| --- | --- | --- |
| [XING WEI 2.4G USB](plugins/bundled/org.justviberemote.device.xingwei-usb/plugin.json) | macOS, Windows | Receiver `1915:1025`, visual button layout |
| [ChatGPT](plugins/bundled/org.justviberemote.app.chatgpt/README.md) | macOS, Windows | Open app, dictation, Send, Backspace, Escape |
| [Antigravity](plugins/bundled/org.justviberemote.app.antigravity/README.md) | macOS | Open app, toggle dictation, Send, Backspace, Escape |
| [Cursor](plugins/bundled/org.justviberemote.app.cursor/README.md) | macOS | Open app, toggle dictation |

Platforms reflect the manifests. Confirm shortcuts in your app; see each plugin’s notes for setup and testing status. Standard USB and Bluetooth HID remotes can be supported through device plugins. Proprietary protocols and Bluetooth audio need separate verification.

## Add remotes and apps

On macOS, use **Add a new remote…** to identify a receiver. If no plugin matches, copy the generated agent prompt and supply a front-facing photo. In a remote’s **Apps** page, use **Add app…** or drop an application from Finder to create a local app profile.

To install a plugin, open **Plugins → Open plugin folder…**, copy its folder there, then click **Reload plugins**. Reload disconnects active sessions. Button mappings are saved per remote and app.

Create plugins with the [agent authoring guide](docs/PLUGIN-AUTHORING.md), [API reference](docs/PLUGINS.md), and [device or app starters](plugins/examples/README.md). For photo-based layouts, see [image-to-plugin](docs/IMAGE-TO-PLUGIN.md). Plugins contain declarative JSON and documentation; the host does not execute plugin scripts or native libraries.

Validate with the .NET 10 SDK:

```sh
dotnet run --project windows/JustVibeRemote.PluginTool -- validate /absolute/path/to/plugin-folder
```

## Build and test

**macOS:** install Apple Command Line Tools. Configure a persistent development signer once, then test and build:

```sh
python3 scripts/local-signing.py setup
./scripts/test-macos.sh
./scripts/build-macos.sh
```

Signing setup creates a local code-signing identity and may request authorization. Alternatively, set `JUSTVIBEREMOTE_SIGNING_IDENTITY` to your Apple Development or Developer ID identity.

**Windows:** install the .NET 10 SDK and run from PowerShell:

```powershell
./scripts/build-windows.ps1
```

Run the portable Windows core tests on macOS, Windows, or Linux:

```sh
dotnet run --project windows/JustVibeRemote.Tests/JustVibeRemote.Tests.csproj -- .
```

## Status and limitations

These are development builds. Local macOS builds are not Apple-notarized; the Windows package has been compiled but has not been run on Windows. The user has verified macOS microphone recording/playback and remote-triggered ChatGPT dictation; the latest ChatGPT shortcut change has not been retested live.

Windows custom actions run alongside native button actions. On macOS, multiple remotes require distinct receiver hardware IDs. Remote cursor settings adjust native speed and acceleration only; physical calibration is not supported.

JustVibe Remote has no telemetry, network client, or audio uploads. Target apps handle their own dictation and privacy behavior. See [trust and local data](docs/TRUST.md) and [architecture](docs/ARCHITECTURE.md).

Shared guides live in `docs/`. Local development notes, research, and artwork prompts belong in `doc/`, which is ignored by Git.

## License

[GNU General Public License v3.0](LICENSE) (`GPL-3.0-only`).
