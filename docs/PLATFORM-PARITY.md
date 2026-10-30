# Platform support review — 2026-10-30

**Status:** Windows implementation and portable checks are available. Native app UI
and physical-device acceptance remain pending on the user's Windows machine.

This is a source/build review, not a claim that Windows hardware or UI tests ran on macOS.
The Windows frontend had a single editor before this change. It now has the same
workspace page families and shared font/spacing system as the Mac frontend.
In the table below, “Implemented” means present in source and cross-compiled; it
does not mean the feature passed a native or physical-device test.

## Pages and capabilities

| Capability | macOS | Windows |
| --- | --- | --- |
| Remotes library and setup entry | Available | Implemented |
| Overview and setup continuation | Available | Implemented |
| App profiles, target paths, active-app routing | Available | Implemented; portable routing checks pass |
| Add local app / drag app into Apps | `.app` identity | `.exe` process identity plus explicit path; optional user-confirmed hold shortcut |
| Buttons, learning, action picker, visual layouts | Available | Implemented |
| Action → Open app, with app-list selection | Selected app launches or activates; target saved per button | Implemented; saved or user-located `.exe`, with running-process path discovery |
| Button test page | Scoped native replacement | Mapped output suspended; native Windows input remains additive |
| Microphone selection, meter, bounded recording/playback/clear | Available | Existing native audio retained; explicit Start is required |
| Microphone identity and default-input safeguard | Available | Existing stable endpoint/default-role checks retained |
| Remote settings and reconnect | Per receiver | Per receiver |
| Remote photo and reset | Available | Local copy; shown in library/overview/settings |
| Installed plugins, search, reload, diagnostics, user folder | Available | Implemented; reload explicitly stops receivers |
| Add remote and agent authoring prompt | Available | Read-only Raw Input discovery; ambiguous matches do not connect |
| Help / connection diagnostics | Available | Implemented; Windows settings and privilege guidance |
| Resumable setup, optional voice, explicit practice confirmation | Available | Implemented; Windows skips Mac permission steps |
| Independent receiver controllers and saved settings | Available | Implemented; shared Raw Input window and output ownership |
| Shared controls without a specific app | Available | Open a chosen app, send/backspace/escape, plus optional Windows voice typing |
| Held-delete repeat | Available | Implemented with focus/testing/learning checks; needs live Windows verification |
| Shortcut entry and recording | Mac key grammar | Windows key grammar, including explicit RALT |
| Single normal process | Available | Existing named mutex retained; UI verification uses isolated temporary settings |
| Offline typography and spacing | Manrope / Inter | Same fonts as private static GDI/GDI+ faces; native DPI scaling |

The shared spacing scale is 4/8/12/16/24/28, with 24-unit card insets and 28-unit
page side margins. The Windows fonts ship inside the app and load privately; no
system font installation or network font download is required. Actual Windows
font rendering and display scaling still need visual inspection.

## Platform boundaries — not equivalent support claims

1. Windows Raw Input observes native keyboard/consumer input. Custom mapped commands
   remain additive. Neither ordinary mapping nor button test claims native-input suppression.
   Do not reintroduce global/exclusive pointer injection to disguise this difference.
2. Native per-receiver cursor speed/acceleration remains macOS-only. Windows Settings
   can adjust system-wide mouse preferences; the Windows UI labels that scope explicitly.
   [SystemParametersInfo defines system-wide parameters](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-systemparametersinfow).
3. API 3 `toggle-shortcut` app plugins remain macOS-only. The validator/schema boundary
   was preserved. The bundled Antigravity plugin is not advertised as Windows-compatible;
   its Windows identity, shortcut and reliable stop behavior need evidence and native tests.
   API 1 Windows hold-shortcut plugins and user-verified local app profiles remain supported.
4. Windows voice typing sends the documented Win+H shortcut to the focused text field.
   Windows owns listening and its UI; this app does not claim a held OS recording session,
   route its audio, or verify another app's input. Stop using the Windows panel or its
   documented voice command. This differs from the targeted macOS Dictation stop mechanism.
   [Microsoft voice typing guide](https://support.microsoft.com/en-us/accessibility/windows/use-voice-typing-to-talk-instead-of-type-on-your-pc).

Raw Input registration is process-wide per device class, so multiple receivers share
one native window and are filtered by observed receiver identities. Disposing one
controller does not unregister another receiver's input.
[Microsoft registration contract](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerrawinputdevices).

Legacy `settings.json` is read without rewriting it; receiver settings live under
`%APPDATA%/JustVibeRemote/remotes/<plugin-id>/settings.json`. Duplicate hardware IDs
cannot run at the same time. Only one receiver may own held shortcut output.
Unknown/ambiguous foreground matches do not activate an app-specific route. Focus
changes invalidate delayed voice starts without changing editor selection or writing
settings. Native Windows voice typing remains a separately confirmed opt-in.

## Verification performed here

- Windows app cross-compilation and self-contained x64/ARM64 publication: passed.
  Both final publish runs completed without warnings or errors. Native runtime tests
  are separate.
- Portable Windows core tests: **228 checks passed**. They cover configuration migration, plugin conformance,
  report decoding, microphone policy, routing/ambiguity, session ownership, shared
  controls, setup persistence, Windows voice fallback, and delayed-start cancellation.
- Mac regression suites: **359 core + 173 receiver-session checks passed**, using synthetic inputs and temporary settings.
- Open app checks cover explicit target selection, per-profile persistence, saved
  and explicit launch paths, legacy Show app settings, shared routing, and removed
  targets. They resolve launch plans without opening apps or sending input.
- No live microphone recording or shortcut injection was started as a build/test side effect.

## Native Windows checks still required

Continue on the user's Windows machine using [WINDOWS-HANDOFF.md](WINDOWS-HANDOFF.md).
The temporary Mac-hosted Windows VM was removed at the user's request before the
app's native UI verification ran. No native app or hardware pass is claimed.

Run `scripts/test-windows-ui.ps1` on Windows. It uses temporary settings and creates
29 page/setup/dialog screenshots plus `verification.json`; it does not start a
receiver, send a shortcut, or capture audio. The runner waits for the preview
process, rejects stale or missing reports, checks the expected screenshot count,
and stops a hung preview after two minutes. Check screenshots at 100%, 150% and
200% DPI, both window sizes, keyboard focus, and font loading. The checked-in
Windows workflow runs the portable checks, native UI verification and both publishes.
It has not been dispatched from this chat.

Then use actual hardware to test:

1. Connect two different receivers; edit one without stopping the other. Reject
   simultaneous profiles for the same VID/PID. Unplug either during held output.
2. Configure different actions for the same control in two apps. Switch focus
   during held and delayed dictation, then to an unsupported app. Confirm release,
   cancellation, no editor/profile mutation, and inactivity for ambiguous matches.
3. Enter button test: mapped actions must pause. Native input remains visible to
   Windows; keep focus in the tester. Relink and cancel without sending mapped actions.
4. Confirm app shortcut, hold/toggle activation, Stop voice, focus-loss handling,
   timeout and release retry. Confirm held-delete repeat stops on release/focus loss.
5. Enumerate inputs without capture. Explicitly start a 5-second preview, stop,
   play, clear, unplug input, and change defaults. Confirm no fallback capture.
6. Check OS voice typing only after explicitly enabling it and confirming Win+H;
   verify fallback versus Everywhere and stopping through Windows' voice panel.
7. Add an `.exe`, preserve configured profiles, resume setup, import/reset a photo,
   search/reload plugins, and reopen independent receiver settings after restart.
8. Assign **Power → Action → Open app → ChatGPT**. Check launch while closed,
   activation while running, changing the chosen app, cancelling the picker,
   restarting the host, and removing the target plugin. Key release and held-button
   repeats must not open it again. Learning and button test must not launch it.
   Held voice output must release before focus changes. The Windows native Power
   behavior remains additive, as described above; it is not suppressed by this Action.
