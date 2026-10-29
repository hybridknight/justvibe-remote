# Make plugins with your coding agent

A plugin should be its own small project. You can update JustVibe Remote without merging custom integrations into the host source.

JustVibe Remote includes `AGENTS.md` instructions at the repository root, in `plugins/`, and inside each starter template. Agents that do not automatically read `AGENTS.md` should be told to read it explicitly. The filename is a convention, not an enforced filesystem boundary; the scope instructions and a final change review still matter.

## Start in a separate folder

1. Copy `plugins/examples/device/` or `plugins/examples/app/` to a new directory outside the JustVibe Remote checkout. Alternatively, extract the matching starter ZIP from `dist/`.
2. Open that new folder in your agent. Its root contains:

   ```text
   my-plugin/
     AGENTS.md
     PLUGIN-GUIDE.md
     plugin.schema.json
     plugin.json
     README.md
     tests/ACCEPTANCE.md
   ```

3. Give the agent the read-only path to the JustVibe Remote source checkout if you have it. The official validator lives there. The portable guide and schema explain the contract even when the host checkout is unavailable.
4. Use one of the prompts below. The agent should edit only this plugin folder. It can read the host checkout and generate validator build outputs, but should not change host source.

Do not customize the original starter in the host repository, put your plugin in `plugins/bundled/`, or replace files inside `JustVibe Remote.app`. Those locations belong to the host release.

## Start with a remote image

Agents can accept a remote photo or packaging image as a visual reference. See [the photo-to-plugin guide](IMAGE-TO-PLUGIN.md) for a copyable prompt and the schema/API 2/2 layout contract. Image evidence establishes shape, labels, and positions; descriptor and live-test evidence still establish hardware behavior. Unclear symbols should be marked, and unverified signal usages left absent.

## Prompt for a remote-device plugin

Copy and fill in this request:

```text
Read AGENTS.md and PLUGIN-GUIDE.md in this plugin folder first.
Create a JustVibe Remote schema 2 / API 2 visual device plugin for [remote model].
The only writable source directory for this task is this plugin folder.
The JustVibe Remote host checkout is at [absolute path, or unavailable]; use it as
reference and for validation, without changing host source, adapters, schemas,
bundled plugins, tests, or build scripts.

Hardware evidence: [USB VID/PID, OS device names, observed HID/report details,
microphone availability, and any supplied documentation].
Target platforms: [macOS, Windows, or both].
Creator namespace/author: [your ID namespace and author name].

Replace all placeholders. Use only the existing hid.standard adapter.
Construct device.layout (layout.version 1) as the single source for the remote
artwork, clickable controls, and mapping-card connectors. Trace the attached
remote photo’s proportions, body style, navigation ring, and visible controls;
use the generic starter only when no image is supplied. Use stable control IDs,
clear labels/icons, and accurate top-left bounds. Preserve IDs across revisions.
The host draws the artwork and places the surrounding mapping cards from this
geometry. Do not draw the surrounding UI into an image, add scripts, or invent
layout fields. Keep button text readable at normal and minimum window sizes.
Read docs/IMAGE-TO-PLUGIN.md in the host checkout if available.

Keep visual evidence separate from hardware evidence. Do not infer hardware
identity, usages, microphone transport, or click/hold gestures from an image.
Leave unverified usage fields absent. Only native, dictate, focus, send,
backspace, and escape are supported default actions; app-specific shortcuts
belong in app plugins. Single/double/long-press mappings are not manifest fields.
If the protocol cannot be expressed in the supported API, document the missing capability
instead of patching the host or inventing manifest fields.
Validate the package, update README.md and tests/ACCEPTANCE.md, and report
static validation separately from live device/platform testing.
Do not install, publish, or overwrite an existing plugin unless requested.
```

No remote details yet? Ask the agent to identify the connected receiver through read-only OS inspection, then request only the missing evidence. A product name alone does not establish VID/PID, report layout, or microphone transport.

## Prompt for an application plugin

```text
Read AGENTS.md and PLUGIN-GUIDE.md in this plugin folder first.
Create a JustVibe Remote API v1 app plugin for [application and version].
The only writable source directory for this task is this plugin folder.
The JustVibe Remote host checkout is at [absolute path, or unavailable]; use it as
reference and for validation without changing host source or validation rules.

Target platforms: [macOS, Windows, or both].
Known app identities and shortcuts: [bundle ID / display name / Windows
process name; exact user-configured or verified shortcut behavior].
Creator namespace/author: [your ID namespace and author name].

Declare only supported actions. Dictation requires a held shortcut; omit it if
that behavior is not verified. Keep user confirmation of dictation shortcuts.
Validate the package and document installation, tested app versions, limitations,
and unverified behavior. If the supported API cannot express an integration, describe the
host capability needed rather than implementing commands or changing the core.
Do not install, publish, or overwrite an existing plugin unless requested.
```

These prompts work with agents beyond Codex. No proprietary agent-specific configuration file is required.

For macOS apps that use press-to-start/press-to-stop dictation, the host also supports schema/API `3/3` with `dictate.operation: "toggle-shortcut"`. Declare only `platforms: ["macos"]`; keep the Windows runtime unsupported. Read the current host contract in PLUGINS.md and validate with a host that supports API 3. The portable API 1 starter continues to describe held shortcuts.

## Validate without modifying the host

With the .NET 10 SDK, use the validator from a known JustVibe Remote checkout. Example in a POSIX shell:

```sh
JUSTVIBE_REMOTE_SOURCE="/absolute/path/to/JustVibeRemote"
PLUGIN_DIR="/absolute/path/to/my-plugin"
dotnet run --project "$JUSTVIBE_REMOTE_SOURCE/windows/JustVibeRemote.PluginTool" -- validate "$PLUGIN_DIR"
```

PowerShell:

```powershell
$JustVibeRemoteSource = "C:\source\JustVibeRemote"
$PluginDir = "C:\plugins\my-plugin"
dotnet run --project "$JustVibeRemoteSource/windows/JustVibeRemote.PluginTool" -- validate "$PluginDir"
```

The validator reads the manifest and does not launch the plugin's target app, read remote input, or send keys. It may build its own ignored outputs and restore Microsoft framework metadata. Do not edit its source to obtain a pass.

If the checkout, SDK, or validator is unavailable, finish the package with the available evidence and clearly label official validation as pending. Structural schema checks alone do not establish semantic compatibility or working hardware.

## Deliver and install

The package README should state:

- Stable plugin ID and its own version.
- Hardware/app identities and the evidence used.
- Platforms declared, platforms actually tested, and any unverified assumptions.
- Configured action behavior, setup, and microphone selection where relevant.
- Official validator result and live-test results.
- Installation/update instructions and known limitations.
- License chosen by the creator, or an explicit undecided-license note.

Copy the complete folder into the community plugin directory using **Plugin folder…**, then **Reload plugins**, select the device/app pair, and Start. JustVibe Remote does not extract ZIPs automatically. Reload first releases the current session; simply copying a package does not activate it.

Do not leave multiple visible folders with the same manifest ID. The loader disables duplicated community IDs. When updating a package, stop the session, keep the old source as a backup outside the plugin directory, replace the installed folder, and Reload.

## Keep core updates independent

```text
JustVibe Remote source/release       Your plugin source             Installed package
host-owned, update normally    separate folder/repository     user plugin directory
             │                          │                              │
             └──── shared API v1 ───────┴──── copy validated package ──┘
```

Keep the plugin ID stable when changing its display name or publishing a new plugin release; learned bindings are keyed by plugin IDs. A host version bump does not require bumping `apiVersion` or `schemaVersion`. Check actual API compatibility instead.

The host's normal release packaging keeps community packages outside its app folders. This preserves files across core updates; it does not promise compatibility with every future breaking API. If compatibility changes, update your package to a supported contract or request an adapter separately. Keep the core checkout free of integration patches so updating it remains straightforward.

## Review the agent's work

The final authored changes should be entirely within the chosen plugin directory. Generated validator `bin/` and `obj/` files do not belong in a plugin release. Check the diff before copying or sharing the package. Agent instructions guide behavior but do not replace an actual review or make an untested plugin trustworthy.

## Automatic active-app mappings

JustVibe Remote can follow the foreground app using the existing `app.targets` identities. No manifest/API change is required. Users configure each installed app plugin once, assign button actions, and enable **Follow active app**. Each device/app pair keeps independent actions and voice settings. Unknown and ambiguous app matches receive no custom action.

Use accurate bundle IDs on macOS and process names (without `.exe`) on Windows. Prefer specific identities over broad display names. An optional user-selected application path takes precedence and can disambiguate overlapping plugins. Identity matching does not authenticate an application's publisher. Agents should include a focus-switch acceptance test: configure two app profiles with different actions on the same button, switch between them, then switch to an unsupported app; verify the expected action, native fallback, and release of held dictation shortcuts.
