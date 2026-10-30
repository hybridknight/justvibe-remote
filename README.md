# JustVibe Remote

**Talk to your agent.**

<img src="assets/branding/JustVibeRemote.svg" width="160" alt="JustVibe Remote: a silver remote with a microphone button over code bars" />

Use a handheld remote to dictate, send prompts, navigate, and trigger shortcuts in your AI apps. Customize buttons for each app and add remote or app support through plugins.

Built for **macOS 13+ on Apple Silicon** and **Windows x64 / ARM64**. Voice input uses the target app’s dictation feature, or optional macOS Dictation across apps; compatibility depends on your hardware and plugins.

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

For native Windows page/layout verification without starting receivers or recording,
run `./scripts/test-windows-ui.ps1` on Windows. See [the platform support review](docs/PLATFORM-PARITY.md)
for the feature matrix, platform boundaries, and live acceptance checks.

Run the portable Windows core tests on macOS, Windows, or Linux:

```sh
dotnet run --project windows/JustVibeRemote.Tests/JustVibeRemote.Tests.csproj -- .
```

## Get started

After building:

- **macOS:** open `dist/JustVibe Remote.app`.
- **Windows:** copy the entire `dist/windows-win-x64` folder to your PC and open `JustVibeRemote.exe`. Keep the folder together; it includes the .NET runtime.

**Test with a real keyboard first.** Open the target app, focus the intended input, and press its shortcut on your keyboard to confirm the action works. For dictation, check whether you must hold the keys while speaking or press once to start and again to stop. Resolve any shortcut or microphone issues in the target app first, then configure the remote with the same keys and matching hold or toggle behavior. For macOS Dictation, test its shortcut in a supported text field before configuring **Dictation in any app**.

On macOS:

1. Open **Remotes**, choose **Set up remote**, and follow the welcome guide.
2. Connect your receiver and grant Input Monitoring and Accessibility when prompted.
3. Choose an app, select a button on the remote diagram, click **Learn this button**, then assign an action.
4. For voice, confirm the app’s dictation shortcut, choose and test the remote’s microphone, and select the same input inside the target app. Save your voice settings.
5. Switch to the target app and try the remote. **Follow active app** uses the configured controls for the app in front.

On macOS, mapped buttons automatically replace their original actions; unmapped buttons keep their normal behavior. This behavior is always enabled. **Buttons** links controls and assigns actions. Choose **Button test…** at the bottom of that page to open a separate test view with the same remote layout. Linked buttons light up when pressed. To test an unlinked button, select it on the picture and press its physical counterpart; that observed signal is saved for the remote across its app profiles. Existing links can be changed with **Relink button**. While test capture is available and that view is in front, presses highlight the remote without sending app actions; macOS exclusive capture is preferred, with a fallback that temporarily blocks the selected receiver’s keyboard and media-button actions using verified device-specific mappings. Those mappings are restored on exit; testing stops if isolation cannot be confirmed. A notice explains when test capture is unavailable. Leave the test page or switch to your target app to resume assigned actions.

### Dictation in any app (macOS)

In the remote’s **Apps** or **Settings** page, choose **Dictation in any app**. It is off by default. Enable Dictation in **macOS System Settings → Keyboard**, then choose and confirm the same shortcut option in JustVibe Remote: the microphone key, Control twice, Globe twice, Right/Left/Either Command twice, or Customize. The microphone-key choice uses Apple’s documented Fn+D Dictation command. For Customize, click the recorder and press your modifier-plus-key chord or a function key (F1–F20, including F13). Select a linked microphone button for the remote. Double-press gestures are sent as cancellable, spaced modifier events, and cleanup releases any partly sent gesture.

Choose **Use when app dictation is not configured** to keep configured native app dictation, or **Use in every app** to use macOS Dictation throughout. Click a supported text field, then press the remote button once to start and again to stop. Stop sends Escape rather than toggling an already-ended recording back on. Profile and focus changes cancel delayed starts; cleanup stays addressed to the original app. The app does not query macOS Dictation’s recording state, so avoid mixing manual controls with an active remote session. Verify focus-change cleanup with your apps.

This is a per-remote host setting; no extra app plugin is needed. It does not change app shortcuts, enable macOS Dictation automatically, select another app’s microphone, or record audio itself. macOS handles recognition according to its settings. See [Apple’s Dictation guide](https://support.apple.com/en-gb/guide/mac-help/mh40584/mac). The feature is macOS-only; live speech recognition and focus-change behavior require manual testing.

Microphone testing starts only when you click **Start 5-second test**. A successful preview does not verify which microphone another app uses.

## Privacy settings

On macOS, open **System Settings → Privacy & Security** and enable **JustVibe Remote** under:

| Permission | Purpose |
| --- | --- |
| Input Monitoring | Read button events from the selected remote. |
| Accessibility | Send configured shortcuts to your apps. |
| Microphone | Optional: record a five-second local microphone test when you start it. |

Approve the exact app you built, then restart JustVibe Remote. If access still fails, open **Connection check…**, reset only the affected permission, and add the current app again. Screen Recording and Full Disk Access are not required.

Dictation uses the target app’s microphone permission and selected input. JustVibe Remote does not upload the local test audio. See [trust and local data](docs/TRUST.md) for details.

## Bundled plugins

| Plugin | Platforms | Controls |
| --- | --- | --- |
| [XING WEI 2.4G USB](plugins/bundled/org.justviberemote.device.xingwei-usb/plugin.json) | macOS, Windows | Receiver `1915:1025`, visual button layout |
| [ChatGPT](plugins/bundled/org.justviberemote.app.chatgpt/README.md) | macOS, Windows | Open app, dictation, Send, Backspace, Escape |
| [Antigravity](plugins/bundled/org.justviberemote.app.antigravity/README.md) | macOS | Open app, toggle dictation, Send, Backspace, Escape |
| [Cursor](plugins/bundled/org.justviberemote.app.cursor/README.md) | macOS | Open app, hold-to-talk dictation |

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

Create plugins with the [agent authoring guide](docs/PLUGIN-AUTHORING.md), [API reference](docs/PLUGINS.md), and [device or app starters](plugins/examples/README.md). For photo-based layouts, see [image-to-plugin](docs/IMAGE-TO-PLUGIN.md). Plugins contain declarative JSON and documentation; the host does not execute plugin scripts or native libraries.

Validate with the .NET 10 SDK:

```sh
dotnet run --project windows/JustVibeRemote.PluginTool -- validate /absolute/path/to/plugin-folder
```

## Status and limitations

These are development builds. Local macOS builds are not Apple-notarized; the Windows package has been compiled but has not been run on Windows. The user has verified macOS microphone recording/playback and remote-triggered ChatGPT dictation; the latest ChatGPT shortcut change has not been retested live.

Windows custom actions run alongside native button actions. On macOS, multiple remotes require distinct receiver hardware IDs. Remote cursor settings adjust native speed and acceleration only; physical calibration is not supported.

## Privacy

JustVibe Remote runs entirely locally. It has no network client, telemetry, or audio uploads. It does not store microphone recordings or dictated text. Optional microphone-test audio stays in memory and is discarded when you close the test or delete the clip.

Your settings, button mappings, plugin files, and selected remote artwork are saved locally on your computer. Target apps handle dictation separately and may send audio to their own services; their privacy policies apply.

See [trust and local data](docs/TRUST.md) and [architecture](docs/ARCHITECTURE.md) for details.

Shared guides live in `docs/`. Local development notes, research, and artwork prompts belong in `doc/`, which is ignored by Git.

## License

[GNU General Public License v3.0](LICENSE) (`GPL-3.0-only`).
