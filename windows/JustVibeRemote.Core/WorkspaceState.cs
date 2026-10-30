namespace JustVibeRemote.Core;

public enum WorkspacePage { Remotes, Overview, Apps, Buttons, Microphone, Settings, Plugins, Help, ButtonTest }
public enum RemoteSetupStage { Welcome, App, Receiver, Button, Microphone, Shortcut, Practice, Done }
public sealed record RemoteSetupCheckpoint(RemoteSetupStage Stage=RemoteSetupStage.Welcome, bool WantsVoice=false);
public enum VoiceTypingMode { Off, Fallback, Everywhere }
public sealed record VoiceTypingSettings(VoiceTypingMode Mode=VoiceTypingMode.Off,string? ControlID=null,bool Confirmed=false)
{
    public void Validate()
    {
        if(!Enum.IsDefined(Mode)||ControlID?.Length>150)throw new InvalidDataException("Invalid Windows voice typing settings.");
        if(Mode!=VoiceTypingMode.Off&&(!Confirmed||string.IsNullOrWhiteSpace(ControlID)))throw new InvalidDataException("Choose a remote button and confirm Windows voice typing before enabling it.");
    }
}
public static class VoiceTypingRouting
{
    public static bool ShouldTrigger(Configuration editor,Configuration? route,string controlID,bool down,bool learning,bool testing)
        => down&&!learning&&!testing&&editor.VoiceTyping.Confirmed&&editor.VoiceTyping.ControlID==controlID&&
           (editor.VoiceTyping.Mode==VoiceTypingMode.Everywhere||editor.VoiceTyping.Mode==VoiceTypingMode.Fallback&&
            (route==null||!route.ShortcutConfirmed||string.IsNullOrWhiteSpace(route.Shortcut)||!route.Bindings.Any(b=>b.ControlID==controlID&&b.Action==ActionKind.Dictate&&b.Usage!=null)));
}
/// Output ownership is separate from the profile displayed in the editor.
public sealed class RemoteSessionOwnership
{
    private readonly Dictionary<string,string> receivers=[];
    public string? VoiceOwner { get; private set; }
    public void Start(string id,string hardwareID)
    {
        if(receivers.Any(p=>p.Key!=id&&p.Value==hardwareID))throw new InvalidOperationException("Another active remote uses the same receiver identity. These profiles cannot be separated by the native adapter.");
        receivers[id]=hardwareID;
    }
    public void Stop(string id){receivers.Remove(id);ReleaseVoice(id);}
    public bool ClaimVoice(string id){if(VoiceOwner!=null&&VoiceOwner!=id)return false;VoiceOwner=id;return true;}
    public void ReleaseVoice(string id){if(VoiceOwner==id)VoiceOwner=null;}
    public bool AllowsOutput(string id)=>VoiceOwner==null||VoiceOwner==id;
}
public sealed class RemoteConfigurationLibrary(string root,Configuration legacy,PluginCatalog catalog)
{
    public ConfigurationStore StoreFor(string id)
    {
        catalog.Find(id,"device");
        return new ConfigurationStore(Path.Combine(root,"remotes",id,"settings.json"));
    }
    public Configuration Load(string id)
    {
        var initial=PluginSelection.Select(legacy,catalog,id,legacy.AppPluginID==Configuration.NoSpecificAppID||catalog.Apps.Any(a=>a.Id==legacy.AppPluginID)?legacy.AppPluginID:Configuration.NoSpecificAppID);
        if(id!=legacy.DevicePluginID)initial=initial with{AutoConnect=false,RemoteSetupCompleted=false,RemoteSetupCheckpoint=null,ArtworkPath="",VoiceTyping=new()};
        var result=StoreFor(id).Load(initial);
        if(result.DevicePluginID!=id)throw new InvalidDataException("Remote settings belong to another receiver. The original file has been preserved.");
        return result;
    }
}

/// A cancelled delayed start can never become output, even after a newer start begins.
public sealed class PendingVoiceStart
{
    private int generation;
    public bool Pending { get; private set; }
    public int Begin(){Pending=true;return ++generation;}
    public void Cancel(){generation++;Pending=false;}
    public bool TryComplete(int ticket,bool running)
    {
        if(!running||!Pending||ticket!=generation)return false;
        Pending=false;return true;
    }
}
