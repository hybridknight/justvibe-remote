# Privacy and permissions

## macOS permissions

On macOS, open **System Settings → Privacy & Security** and enable **JustVibe Remote** under:

| Permission | Purpose |
| --- | --- |
| Input Monitoring | Read button events from the selected remote. |
| Accessibility | Send configured shortcuts to your apps. |
| Microphone | Optional: record a five-second local microphone test when you start it. |

Approve the exact app you built, then restart JustVibe Remote. If access still fails, open **Connection check…**, reset only the affected permission, and add the current app again. Screen Recording and Full Disk Access are not required.

Dictation uses the target app’s microphone permission and selected input. JustVibe Remote does not upload the local test audio. See [trust and local data](https://github.com/hybridknight/justvibe-remote/blob/main/docs/TRUST.md) for details.


## Privacy and local data

JustVibe Remote runs entirely locally. It has no network client, telemetry, or audio uploads. It does not store microphone recordings or dictated text. Optional microphone-test audio stays in memory and is discarded when you close the test or delete the clip.

Your settings, button mappings, plugin files, and selected remote artwork are saved locally on your computer. Target apps handle dictation separately and may send audio to their own services; their privacy policies apply.

See [trust and local data](https://github.com/hybridknight/justvibe-remote/blob/main/docs/TRUST.md) and [architecture](https://github.com/hybridknight/justvibe-remote/blob/main/docs/ARCHITECTURE.md) for details.

Shared guides live in `docs/`. Local development notes, research, and artwork prompts belong in `doc/`, which is ignored by Git.
