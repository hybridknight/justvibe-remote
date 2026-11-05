# Prompts for your AI assistant

Copy one of the prompts below into your coding assistant. Replace the bracketed
details you know; leave the others as “unknown.” If you have this source checkout,
open it in your assistant or provide its absolute path so the assistant can read
the guides. These prompts work with assistants beyond Codex.

## Set up my remote

Use this for first-time setup or troubleshooting. You can attach a photo of your
remote and share the exact status message shown in JustVibe Remote.

```text
Help me set up my remote with JustVibe Remote. Guide me through short, practical
steps, check the result at each stage, and use the instructions for my platform.

My computer and OS version: [macOS or Windows, version]
JustVibe Remote version and source checkout path: [version; absolute path or unknown]
Remote model and connection: [model; USB receiver, USB cable, or Bluetooth]
Target app and version: [app and version]
What I want the buttons to do: [dictation, Send, navigation, or other actions]
Current progress or problem: [not started, status message, or what fails]
Microphone I want to use: [remote microphone, another input, or unknown]

If the source checkout is available, read AGENTS.md, README.md,
docs/wiki/Getting-started.md, and the relevant platform guide, including
docs/WINDOWS-SETUP.md on Windows. Use authorized read-only local inspection to
find available details before asking me for missing information. Do not assume
you can inspect my computer if you have no local access.

Start with the existing release and installed device/app plugins. Help me connect
the receiver or pair Bluetooth in system settings, select the correct remote and
app profile, learn the physical buttons, and assign actions. Explain any OS
permissions I need to grant myself. Do not build or modify the core app as a
normal setup step.

Before mapping dictation, have me test the target app's shortcut on a real
keyboard with its text input focused. Establish whether the app expects a held
shortcut or a press-to-start/press-to-stop shortcut; do not guess from its name
or assume a remote activation option converts one behavior into the other.
Keep the app's shortcut confirmation step.

Configure audio separately from button shortcuts. Selecting a microphone in
JustVibe does not change the target app's input or prove which microphone it
uses. On Windows, follow the guide for both Default Device and Default
Communication Device and check the app's own input selection. A generic audio
device name alone does not prove it is the remote microphone. Do not start a
recording automatically; explain the optional local five-second test so I can
choose to start it. Close the microphone-test dialog before testing dictation.

Test the mapped buttons in the target app, including stopping dictation. If I
use Follow active app, check routing across configured profiles and an
unsupported app, including changing focus while dictation is held. Explain
that the profile displayed in the editor is separate from active-app routing.
Use status messages to narrow down failures; distinguish connection, button
learning, shortcut output, microphone input, and transcription.

If my remote or app has no suitable plugin, explain the missing support before
creating anything. For a new remote plugin, read docs/PLUGIN-AUTHORING.md,
docs/PLUGINS.md, plugins/AGENTS.md, and docs/IMAGE-TO-PLUGIN.md. Copy the device
starter to a separate writable folder outside the host checkout, keeping its
instructions, guide, schema, and acceptance notes. Use hid.standard and
schema/API 2/2 for a visual layout. A photo supplies visible geometry and labels
only; obtain hardware IDs and report information from device evidence, leave
unverified usages absent, and do not infer microphone transport from a photo.
If app support is missing, use the app-plugin workflow in PROMPT.md.
Do not patch the host or invent manifest fields for unsupported behavior.

Finish with what is working, what I still need to do, and what remains untested.
Do not claim a hardware, audio, or platform test that we did not perform.
```

See also: [Getting started](docs/wiki/Getting-started.md) and
[Windows setup and dictation](docs/WINDOWS-SETUP.md).

## Add support for a new app

Use this to create an app plugin. A separate device plugin handles the remote;
you do not need a new device plugin for each app.

```text
Create a JustVibe Remote app plugin for the application below.

App name and version: [name and version]
Target platforms: [macOS, Windows, or both]
Desired actions: [open/focus, dictation, Send, Backspace, Escape]
Known shortcuts and behavior: [exact keys; held or toggle; unknown if untested]
Known app identity: [macOS bundle ID or Windows process name, or unknown]
JustVibe Remote source checkout: [absolute path or unavailable]
New plugin source folder: [absolute path outside the host checkout, or suggest one]
Creator namespace and author: [my namespace and name, or ask me]
Plugin license: [my chosen license, or undecided]

Read the host's AGENTS.md, docs/PLUGIN-AUTHORING.md, docs/PLUGINS.md, and
plugins/AGENTS.md if available. Check whether an installed or bundled plugin
already meets this need before creating a duplicate. Use local inspection,
official app documentation, and my verified settings to establish identities
and shortcuts. Ask only for missing facts; do not guess support claims.

Copy plugins/examples/app/ into the separate plugin source folder. If the host
checkout is unavailable, use the matching official app starter if supplied;
otherwise explain that it is needed before authoring the package. Read and keep
the copied AGENTS.md, PLUGIN-GUIDE.md, schema, and tests/ACCEPTANCE.md.
Confine authored changes to this plugin folder. Treat host source, bundled
plugins, adapters, schemas, validators, and build scripts as read-only references.

Use the existing shortcuts adapter and schema/API 1/1. Choose a stable plugin
ID in my namespace and a separate plugin release version; do not reuse a bundled
ID. Declare only supported actions and platforms with evidenced identities and
shortcuts. Windows process names exclude .exe. Include dictation only when the
required held-shortcut behavior is verified, and preserve user confirmation of
the shortcut. If this contract cannot express the app's behavior, document the
missing capability as a separate host request instead of modifying core code,
changing API versions, or inventing fields. Do not add scripts, commands,
executable paths, network dependencies, or audio capture/routing.

From the host source root, run the official validator with the .NET 10 SDK:
dotnet run --project windows/JustVibeRemote.PluginTool -- validate /absolute/path/to/plugin-folder

Fix the plugin rather than weakening validation. If the checkout, SDK, or
validator is unavailable, report official validation as pending with the reason.
Schema checks are not a substitute. Plugin work does not require building or
launching the core app or granting OS permissions.

Include plugin.json, setup instructions, evidence and limitations, the starter
instructions and acceptance notes, and my chosen license or an explicit note
that licensing is undecided. Record exact validator results separately from
live tests. Provide acceptance steps for each action and Follow active app:
use the same remote button across two configured profiles and an unsupported
app, including changing focus during held dictation and checking key release.
Do not mark these tests passed unless actually performed.

Provide installation instructions using Plugin folder… and Reload plugins:
macOS: ~/Library/Application Support/JustVibeRemote/plugins/<plugin-folder>/
Windows: %APPDATA%/JustVibeRemote/plugins/<plugin-folder>/
Keep the source copy separate. Do not install, publish, or overwrite existing
plugins unless I request it. Do not install inside the app bundle or bundled
plugin source directory, or leave duplicate community plugin IDs installed.

Review the final changes for scope. Report the plugin folder, ID/version,
supported capabilities, exact validation result, live-test status, installation
steps, and “Core host source changed: no” when accurate.
```

See also: [Plugin authoring](docs/PLUGIN-AUTHORING.md) and
[plugin contract](docs/PLUGINS.md).
