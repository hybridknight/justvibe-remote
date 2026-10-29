namespace JustVibeRemote.Core;
public enum SetupStep { InputPermission, ShortcutPermission, Receiver, Microphone, Shortcut, Test, Ready }
public sealed record SetupProgress(bool InputAllowed,bool ShortcutsAllowed,bool ReceiverConnected,bool NeedsDictation,bool MicrophoneLinked,bool ShortcutConfirmed,bool TestConfirmed)
{
    public SetupStep Step => !InputAllowed ? SetupStep.InputPermission : !ShortcutsAllowed ? SetupStep.ShortcutPermission : !ReceiverConnected ? SetupStep.Receiver : !NeedsDictation ? SetupStep.Ready : !MicrophoneLinked ? SetupStep.Microphone : !ShortcutConfirmed ? SetupStep.Shortcut : !TestConfirmed ? SetupStep.Test : SetupStep.Ready;
}
