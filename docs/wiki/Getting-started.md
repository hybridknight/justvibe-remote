# Getting started

After building:

- **macOS:** open `dist/JustVibe Remote.app`.
- **Windows:** copy the entire `dist/windows-win-x64` folder to your PC and open `JustVibeRemote.exe`. Keep the folder together; it includes the .NET runtime.

**Test with a real keyboard first.** Open the target app, focus the intended input, and press its shortcut on your keyboard to confirm the action works. For dictation, check whether you must hold the keys while speaking or press once to start and again to stop. Resolve any shortcut or microphone issues in the target app first, then configure the remote with the same keys and matching hold or toggle behavior. For macOS Dictation, test its shortcut in a supported text field before configuring **Dictation in any app**.

**Windows:** follow the [Windows setup and dictation guide](https://github.com/hybridknight/justvibe-remote/blob/main/docs/WINDOWS-SETUP.md). It covers linking the microphone button, confirming the app shortcut, setting both Windows microphone defaults, and resolving blocked dictation.

On macOS:

1. Open **Remotes**, choose **Set up remote**, and follow the welcome guide.
2. Connect your receiver and grant Input Monitoring and Accessibility when prompted.
3. Choose an app, select a button on the remote diagram, click **Learn this button**, then assign an action.
4. For voice, confirm the app’s dictation shortcut, choose and test the remote’s microphone, and select the same input inside the target app. Save your voice settings.
5. Switch to the target app and try the remote. **Follow active app** uses the configured controls for the app in front.

On macOS, mapped buttons automatically replace their original actions; unmapped buttons keep their normal behavior. This behavior is always enabled. **Buttons** links controls and assigns actions. Choose **Button test…** at the bottom of that page to open a separate test view with the same remote layout. Linked buttons light up when pressed. To test an unlinked button, select it on the picture and press its physical counterpart; that observed signal is saved for the remote across its app profiles. Existing links can be changed with **Relink button**. While test capture is available and that view is in front, presses highlight the remote without sending app actions; macOS exclusive capture is preferred, with a fallback that temporarily blocks the selected receiver’s keyboard and media-button actions using verified device-specific mappings. Those mappings are restored on exit; testing stops if isolation cannot be confirmed. A notice explains when test capture is unavailable. Leave the test page or switch to your target app to resume assigned actions.


For system-wide voice input, see [Dictation in any app](Dictation-in-any-app). For permissions, see [Privacy and permissions](Privacy-and-permissions).
