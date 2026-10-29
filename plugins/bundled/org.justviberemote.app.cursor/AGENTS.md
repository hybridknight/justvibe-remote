# Agent task: JustVibe Remote app plugin

Read `PLUGIN-GUIDE.md` before editing. These instructions travel with this folder when it becomes an independent plugin project.

## Scope

This plugin directory is the only writable source scope for an integration request. Treat any JustVibe Remote checkout as a reference/validator, not a fork. Do not edit native output code, plugin loaders, bundled plugins, schemas, validators, or host tests to make this package work.

Keep `plugin.schema.json` as the supplied reference snapshot. If the user explicitly asks to maintain these starter instructions rather than build a plugin, edit the requested documentation instead.

## Build the plugin

1. Identify the app and relevant version. Verify macOS bundle IDs/display names and Windows process names; do not use executable paths or command lines in the manifest.
2. Verify shortcut behavior from the user's actual settings, authorized local inspection, or reliable app documentation. Suggestions are not proof of current defaults.
3. Replace all template metadata using the creator's own stable namespace. Never override a bundled plugin ID.
4. Use `shortcuts` with `target.focus` and `input.shortcuts`. Provide `focus`; declare only optional intents the app actually supports.
5. Use `hold-shortcut` for `dictate` only if a held shortcut starts/stops dictation. Toggle-only voice and live voice chat are not the same contract. Omit unsupported dictation rather than emulating it with commands.
6. Use `tap-shortcut` for supported `send`, `backspace`, and `escape` intents. Include shortcuts and target identities for every declared platform.
7. Keep actions bounded to the host's supported shortcut grammar. No shell commands, scripts, arbitrary macro sequences, network calls, paths, or helper executables.
8. Validate with the official tool if available. Update `tests/ACCEPTANCE.md` and README with app versions, actual tests, limitations, and installation steps.

## Updates and delivery

Keep the plugin ID stable. Keep host API/schema versions at supported values; they do not track the app or host's release version. Let the host manage user confirmation, foreground checks, shortcut ownership, and cleanup.

If API v1 cannot express the desired behavior, document a separate host capability request. Do not work around it by modifying the core or weakening validation.

Deliver the folder, ID/version, validation result, tested/unverified behavior, and install instructions. State “Core host source changed: no” when accurate. Do not install, publish, grant permissions, or replace another package unless requested.

## Remote photos

A supplied remote image belongs to the separate device plugin's layout. Do not add device geometry or guessed HID usages to an app plugin. App identities and shortcuts still need their own evidence; keep this app manifest at schema/API `1/1`.


## Bundled Cursor scope and API 3

The user explicitly requested bundled Cursor support. This package is host-maintained bundled-plugin work. It uses macOS-only schema/API 3/3 with toggle-shortcut dictation, as documented in the host docs/PLUGINS.md; this supersedes the starter's API 1 held-only restrictions. Keep the reference schema snapshot unchanged. Control+M and press-to-start / press-to-stop behavior were supplied and confirmed by the user. Preserve org.justviberemote.app.cursor as the bundled ID. Do not claim Windows or live app verification.
