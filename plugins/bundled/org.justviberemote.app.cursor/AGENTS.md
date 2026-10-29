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


## Bundled Cursor scope and Control+M hold

This package is host-maintained bundled-plugin work. Preserve org.justviberemote.app.cursor and the reference schema snapshot. Use macOS-only schema/API 1/1 and hold-shortcut dictation. On 2026-10-30 the user explicitly chose to keep Control+M and hold the remote button while talking. This supersedes the previous tap-to-start/tap-to-stop requirement. Cursor’s installed command is Hold to Talk. Configure the saved Cursor profile with voiceMode hold; do not change Cursor’s keybindings or install an external dictation tool. Do not claim Windows or unperformed live verification.

## XING WEI mic pulse evidence and current activation

On 2026-10-30 an input-only check observed approximately 120 ms mic pulses even during user-reported three-second physical holds. The user then explicitly chose: press once to hold Control+M; press again to release it. This supersedes physical hold activation for this receiver. Keep hold-shortcut output and use voiceMode toggle for its Cursor profile. Do not confuse a toggled remote activation with the plugin’s toggle-shortcut operation: Cursor still requires a held keyboard chord.
