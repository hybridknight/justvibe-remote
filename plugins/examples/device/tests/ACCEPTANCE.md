# Device plugin acceptance record

Fill in actual results. Do not mark a behavior verified from a validator pass.

- Plugin ID/version: pending
- Creator: pending
- Remote model/revision: pending
- Receiver VID/PID and OS names: pending
- Evidence source for HID/report layout: pending
- Declared platforms: pending
- Native microphone evidence, or `audio: none`: pending
- Official validator command/result: not run
- Core host source changed: no (verify before delivery)

## Live behavior

| Check | macOS | Windows | Evidence/notes |
| --- | --- | --- | --- |
| Selected receiver is recognized; other device identities ignored | Not tested | Not tested | |
| Physical buttons learn the expected usages | Not tested | Not tested | |
| Press/release or pulse behavior is understood | Not tested | Not tested | |
| Native pointer/button behavior matches documented limits | Not tested | Not tested | |
| Stop/disconnect ends the active dictation session | Not tested | Not tested | |
| Microphone transmits usable audio, if claimed | Not tested | Not tested | |
| Package installs through the external plugin directory and Reload | Not tested | Not tested | |

## Limitations and remaining work

Record unsupported protocol features and pending tests. A device not available to the agent remains untested. Do not patch the host to clear a plugin acceptance item.

## Image/layout evidence

- Supplied image(s) / source / visible face: pending or not applicable
- Visible geometry and labels traced: pending or not applicable
- Unclear symbols and unshown controls: pending or not applicable
- Hardware facts verified separately from the photo: pending
- Stable control IDs retained across revisions: pending or not applicable
- Layout manifest validation: not run
- Graphic selection, legibility, and keyboard access tested: not tested
- No HID usages or microphone transport inferred from image alone: verify before delivery

## Artwork and mapping-board compatibility

- Artwork matches the supplied remote (or explicitly uses generic geometry): pending
- Stable IDs, labels, icons, body style, and all bounds validated: pending
- Every drawn control corresponds to its mapping card: not tested
- Selecting artwork/card highlights the same control and connector: not tested
- Connector anchor centers align with visible controls: not tested
- Labels and action menus remain usable at minimum window size: not tested
- Retained legacy bindings remain accessible through button details: not tested
- No unsupported gesture, image, script, or UI fields added: verify before delivery
