# Plugin workspace instructions

These instructions apply under `plugins/`. Closer `AGENTS.md` files add role-specific instructions. For a standalone plugin, copy its template's agent instructions into that plugin's root.

## Directory ownership

- `bundled/`: host-maintained plugins shipped with JustVibe Remote. Do not put community plugins here or edit these as a shortcut to adding an integration.
- `examples/`: starter templates, not installed plugins. Copy a template before customizing it. Edit a template itself only when the user asks to improve the starter/documentation.
- `tests/`: shared host conformance fixtures. Do not change expected results to accommodate an invalid community plugin.
- `plugin.schema.json`: host API contract. Do not weaken it for a plugin.

A normal integration should touch only the user-selected plugin directory, preferably outside this repository. Read host files as needed; do not modify the native app, generic adapters, loader, schema, or validator.

## Workflow

1. Determine device vs app support. These are separate plugins; do not put both payloads in one manifest.
2. Read `docs/PLUGINS.md` and `docs/PLUGIN-AUTHORING.md` from the host repository if available.
3. Collect required facts before writing support claims. Ask only for missing facts that cannot be determined from authorized local inspection or supplied documentation.
4. Edit the copied manifest and package documentation. Keep the declared API constraints and the creator's stable ID.
5. Run the official validator with the host checkout as a reference. Fix the plugin, never the validator.
6. Use the copied acceptance notes to distinguish validation from actual behavior tests.
7. Check scope and provide a ready-to-copy folder. Installing it is a separate step unless requested.

Do not automatically download community code, run arbitrary vendor helpers, publish a plugin, overwrite another package, or grant OS access as part of authoring. A declarative plugin can still send impactful shortcuts to its target app; explain the configured behavior plainly.

## Host updates

Installed community packages live in:

- macOS: `~/Library/Application Support/JustVibeRemote/plugins/<plugin-folder>/`
- Windows: `%APPDATA%/JustVibeRemote/plugins/<plugin-folder>/`

Keep a separate source copy/repository for the plugin. Update JustVibe Remote independently. If a later host rejects the package, check its published API compatibility first; update the plugin only if the supported API can express the change. An unsupported adapter is a host feature request, not permission to maintain a patched host fork.

## Photo-driven device layouts

A remote image is a valid starting input. Use schema/API `2/2` for the device's visual layout and the supplied layout schema. Read `docs/IMAGE-TO-PLUGIN.md` in the host checkout, or the portable guide in the copied starter. Geometry, labels, shape, and uncertain symbols can come from the image. Hardware identity, report decoding, usage codes, and microphone transport need separate evidence. Leave unverified usages absent and let the user learn them.

Keep the layout and reference notes inside the plugin project. No host-renderer changes are needed for supported controls, icons, body styles, or positions. App plugins remain independent of the remote's picture.
