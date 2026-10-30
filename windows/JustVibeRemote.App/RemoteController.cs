using Binding = JustVibeRemote.Core.Binding;
using JustVibeRemote.Core;

namespace JustVibeRemote;

internal sealed class RemoteController
{
    private readonly AppLaunchCycle launchCycle=new();
    public ConfigurationStore Store { get; }
    private readonly string pluginDirectory;
    public Action? ValidateStart, Stopped, ReleaseVoice;
    public Func<bool>? ClaimVoice, MaySendOutput;
    public bool ButtonTesting { get; private set; }
    public void SetButtonTest(bool enabled){if(ButtonTesting==enabled)return;CancelLearning();StopVoice();ButtonTesting=enabled;Changed?.Invoke();}
    public Configuration Config { get; private set; }
    public PluginCatalog Catalog { get; private set; }
    public string PluginDirectory => pluginDirectory;
    public PluginManifest? AppPlugin => Catalog.Apps.FirstOrDefault(p => p.Id == Config.AppPluginID);
    public PluginManifest? DevicePlugin => Catalog.Devices.FirstOrDefault(p => p.Id == Config.DevicePluginID);
    public RemoteLayout Layout => DevicePlugin?.Device?.Layout ?? RemoteLayout.Generic(Config.Bindings);
    public HashSet<Usage> ActiveUsages { get; } = [];
    public int? LearningIndex => learning;
    public bool VoiceActive => voice.Held || pending || output.HasHeldKeys;
    public ActionKind[] AvailableActions => Enum.GetValues<ActionKind>().Where(action => action is ActionKind.Native or ActionKind.Focus || (AppPlugin?.App??(Config.AppPluginID==Configuration.NoSpecificAppID?SharedActions.Plugin:null))?.Supports(action) == true).ToArray();
    public string Status { get; private set; } = "Ready to set up your remote";
    public bool Running { get; private set; }
    public int Connected { get; private set; }
    public event Action? Changed;
    public bool MicrophoneTesting { get; private set; }
    public string MicrophoneSummary=>Config.Microphones.TryGetValue(Config.DevicePluginID,out var mic)?$"Remote mic: {mic.Name} · system-input safeguard {(mic.GuardDictation?"on":"off")} · app input unverified":"Microphone not selected — open Microphone test";
    public void BeginMicrophoneTest(){CancelLearning();StopVoice();MicrophoneTesting=true;}
    public void EndMicrophoneTest(){MicrophoneTesting=false;Changed?.Invoke();}
    public int? MicrophoneIndex { get { int index=Config.Bindings.FindIndex(b=>b.ControlID=="microphone"||b.Action==ActionKind.Dictate);return index<0?null:index; } }
    public SetupProgress SetupProgress => new(true,true,Running&&Connected>0,AppPlugin?.App?.Supports(ActionKind.Dictate)==true,MicrophoneIndex is int index&&Config.Bindings[index].Usage!=null&&Config.Bindings[index].Action==ActionKind.Dictate,Config.ShortcutConfirmed,Config.DictationTested);
    public void ResumeIfConfigured(){if(Config.AutoConnect)Start();}
    public void ShowTargetApp(){try{if(Config.AppPluginID==Configuration.NoSpecificAppID){Status="Switch to the app where you want to use your shared controls.";Changed?.Invoke();return;}var display=new TargetOutput{Plugin=Catalog.Find(Config.AppPluginID,"app").App};display.Show(Config);}catch(Exception error){Status=error.Message;Changed?.Invoke();}}
    private Usage? repeatUsage;
    private Configuration? repeatRoute;
    private DateTime repeatAfter;
    private readonly System.Windows.Forms.Timer repeatTimer=new(){Interval=80};
    private NativeInput? input;
    private readonly TargetOutput output = new();
    private readonly VoiceSession voice = new();
    private readonly System.Windows.Forms.Timer timer = new() { Interval = 250 };
    private readonly PendingVoiceStart voiceStart=new();
    private bool pending=>voiceStart.Pending;
    private int? learning;
    private Configuration? routedConfig;
    private string routeKey="";
    public string RoutingLabel { get; private set; }="Using selected app";
    private void SynchronizeRoute(bool force=false)
    {
        if(!Running)return;
        var front=TargetOutput.Foreground();
        var next=AppRouting.Resolve(Config,Catalog.Apps,front);
        string key=Config.FollowActiveApp||Config.AppPluginID==Configuration.NoSpecificAppID?(front?.Instance??"none")+"|"+(next?.AppPluginID??"native"):Config.AppPluginID;
        if(!force&&key==routeKey)return;
        FinishVoice();
        if(output.HasHeldKeys){routedConfig=null;return;}
        routeKey=key;routedConfig=next;output.Plugin=next==null?null:next.AppPluginID==Configuration.NoSpecificAppID?SharedActions.Plugin:Catalog.Find(next.AppPluginID,"app").App;
        RoutingLabel=DescribeRoute(Config.FollowActiveApp,next,Catalog);
        Changed?.Invoke();
    }
    internal static string DescribeRoute(bool follow,Configuration? route,PluginCatalog catalog)=>!follow?"Using selected app":route==null?"Active app: original remote actions":route.AppPluginID==Configuration.NoSpecificAppID?"Active mapping: shared controls":"Active mapping: "+catalog.Find(route.AppPluginID,"app").Name;
    public RemoteController(ConfigurationStore? store=null,Configuration? initial=null,string? pluginDirectory=null)
    {
        Store=store??new(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),"JustVibeRemote","settings.json"));
        this.pluginDirectory=pluginDirectory??Path.Combine(Path.GetDirectoryName(Store.Path)!,"plugins");
        Catalog = new PluginCatalog(Path.Combine(AppContext.BaseDirectory, "plugins"), PluginDirectory);
        var device = Catalog.Devices.FirstOrDefault(p => p.Id == new Configuration().DevicePluginID); var app = Catalog.Apps.FirstOrDefault(p => p.Id == new Configuration().AppPluginID);
        var defaults = new Configuration();
        if (device != null) defaults = defaults with { DevicePluginID = device.Id, Profile = device.Device!.Profile };
        if (app != null) defaults = defaults with { AppPluginID = app.Id, Shortcut = app.App!.Supports(ActionKind.Dictate) ? app.App.Shortcut(ActionKind.Dictate) : "" };
        Config = Store.Load(initial??defaults);
        if (File.Exists(Store.Path))
        {
            using var document = System.Text.Json.JsonDocument.Parse(File.ReadAllText(Store.Path));
            if (!document.RootElement.TryGetProperty("devicePluginID", out _))
                Config = Config with { DevicePluginID = Catalog.Devices.FirstOrDefault(p => p.Device!.Profile.VendorId == Config.Profile.VendorId && p.Device.Profile.ProductId == Config.Profile.ProductId)?.Id ?? "" };
        }
        if (DevicePlugin?.Device?.Layout is { } layout) Config = Config with { Bindings = layout.Bindings(File.Exists(Store.Path) ? Config.Bindings : null) };
        timer.Tick += (_, _) => {
            SynchronizeRoute();
            if (output.HasHeldKeys && !voice.Held) { FinishVoice(); return; }
            if(voice.Held){try{AudioInputs.Check(Config.Microphones.GetValueOrDefault(Config.DevicePluginID));}catch(Exception error){FinishVoice();Status=error.Message;Changed?.Invoke();}}
            if (voice.Held && (voice.Expired(DateTimeOffset.UtcNow) || !(routedConfig!=null&&output.IsTargetFrontmost(routedConfig)))) FinishVoice();
        };
        repeatTimer.Tick+=(_,_)=>{
            if(repeatUsage is not Usage usage||repeatRoute is not {} route||!ActiveUsages.Contains(usage)||!Running||MicrophoneTesting||ButtonTesting||learning!=null||MaySendOutput?.Invoke()==false||!output.IsTargetFrontmost(route)){repeatTimer.Stop();repeatUsage=null;return;}
            if(DateTime.UtcNow<repeatAfter)return;
            try{output.Tap(ActionKind.Backspace);}catch(Exception error){repeatTimer.Stop();repeatUsage=null;Status=error.Message;Changed?.Invoke();}
        };
        timer.Start();
    }
    public void Start()
    {
        if (Running) return;
        try
        {
            ValidateStart?.Invoke();
            var device = Catalog.Find(Config.DevicePluginID, "device");
            output.Plugin = AppPlugin?.App;
            Config = Config with { Profile = device.Device!.Profile };
            input = new NativeInput(Config.Profile);
            input.Edge += Handle;
            input.Disconnected += () => { ActiveUsages.Clear(); FinishVoice(); Status = "Receiver disconnected; voice shortcut released"; Changed?.Invoke(); };
            input.DevicesChanged += count => { Connected = count; Status = count > 0 ? "Receiver connected · app plugin ready" : "Waiting for USB receiver…"; Changed?.Invoke(); };
            input.Error += message => { Status = message; FinishVoice(); Changed?.Invoke(); };
            Running = true; SynchronizeRoute(true); input.RefreshDevices();
        }
        catch (Exception error) { input?.Dispose(); input = null; Running=false;Stopped?.Invoke();Status = error.Message; }
        Changed?.Invoke();
    }
    public void Stop()
    {
        repeatTimer.Stop();repeatUsage=null;
        Running = false; routedConfig=null; routeKey=""; ActiveUsages.Clear(); voiceStart.Cancel(); learning = null;
        input?.Dispose(); input = null; Connected = 0;
        output.Release(); voice.Commit(false, DateTimeOffset.UtcNow);ReleaseVoice?.Invoke();Stopped?.Invoke();
        Status = "Stopped; voice shortcut released"; Changed?.Invoke();
    }
    public void Update(Configuration configuration)
    {
        if(configuration.AppPluginID==Config.AppPluginID&&configuration.DevicePluginID==Config.DevicePluginID&&(configuration.Shortcut!=Config.Shortcut||configuration.ShortcutConfirmed!=Config.ShortcutConfirmed||configuration.TargetAppPath!=Config.TargetAppPath||configuration.VoiceMode!=Config.VoiceMode||!configuration.Bindings.SequenceEqual(Config.Bindings)))
            configuration=configuration with{DictationTested=false};
        if(configuration.Microphones.GetValueOrDefault(configuration.DevicePluginID)?.Id!=Config.Microphones.GetValueOrDefault(configuration.DevicePluginID)?.Id)
            configuration=configuration with{DictationTested=false,AppMappings=configuration.AppMappings.ToDictionary(p=>p.Key,p=>p.Key.StartsWith(configuration.DevicePluginID+"|",StringComparison.Ordinal)?p.Value with{DictationTested=false}:p.Value)};
        configuration.Validate();
        Catalog.Find(configuration.DevicePluginID, "device");
        var app = configuration.AppPluginID==Configuration.NoSpecificAppID?null:Catalog.Find(configuration.AppPluginID, "app").App;
        if (app?.Supports(ActionKind.Dictate)==true&&(configuration.ShortcutConfirmed||!string.IsNullOrWhiteSpace(configuration.Shortcut))) TargetOutput.ParseShortcut(configuration.Shortcut);
        bool restart = Running;
        Stop(); Store.Save(configuration); Config = configuration;
        if (restart) Start();
        Changed?.Invoke();
    }
    public void ApplyActionToAllApps(int index)
    {
        var result=PluginSelection.ApplyActionToAllApps(Config,index,Catalog);
        Update(result.Config);
        Status=$"Applied to {result.Applied} app profiles on this remote."+(result.Skipped.Count==0?"":" Unsupported action in: "+string.Join(", ",result.Skipped)+".");
        Changed?.Invoke();
    }
    public void SaveSetup(RemoteSetupCheckpoint checkpoint,bool? completed=null){var next=Config with{RemoteSetupCheckpoint=checkpoint,RemoteSetupCompleted=completed??Config.RemoteSetupCompleted};Store.Save(next);Config=next;Changed?.Invoke();}
    public void SelectPlugins(string deviceID, string appID)
    {
        Update(PluginSelection.Select(Config, Catalog, deviceID, appID));
    }
    public void RefreshCatalog(){Catalog=new PluginCatalog(Path.Combine(AppContext.BaseDirectory,"plugins"),PluginDirectory);}
    public void ReloadPlugins()
    {
        Stop(); Catalog = new PluginCatalog(Path.Combine(AppContext.BaseDirectory, "plugins"), PluginDirectory);
        if (DevicePlugin?.Device?.Layout is { } layout) Config = Config with { Bindings = layout.Bindings(Config.Bindings) };
        Status = "Plugins reloaded; connect your remote when ready. " + string.Join(" · ", Catalog.Diagnostics); Changed?.Invoke();
    }
    public void CancelLearning() { if (learning == null) return; learning = null; Status = "Button learning cancelled"; Changed?.Invoke(); }
    public void Learn(int index)
    {
        if (index < 0 || index >= Config.Bindings.Count) return;
        if (!Running) { Status = "Connect your remote before learning a button"; Changed?.Invoke(); return; }
        FinishVoice(); learning = index; Status = $"Press only the {Config.Bindings[index].Name} button once…"; Changed?.Invoke();
    }
    public void StopVoice() => FinishVoice();
    public void TestVoice()
    {
        if (!Running) { Status = "Connect your remote first"; Changed?.Invoke(); return; }
        if (VoiceActive) FinishVoice();
        else if(Config.FollowActiveApp){ShowTargetApp();Status="Use the remote’s microphone button in the app to test its active mapping";Changed?.Invoke();}
        else if(routedConfig!=null)BeginVoice(routedConfig);
    }
    private void Handle(Usage usage, bool down)
    {
        if (!Running) return;
        bool repeatedDown=down&&ActiveUsages.Contains(usage);
        if(!down&&repeatUsage==usage){repeatTimer.Stop();repeatUsage=null;}
        if (down) ActiveUsages.Add(usage); else ActiveUsages.Remove(usage);
        Changed?.Invoke();
        try
        {
            if (learning is int index)
            {
                if (!down) return;
                var bindings = Config.Bindings.Select((binding, row) => row == index ? binding with { Usage = usage } : binding.Usage == usage ? binding with { Usage = null } : binding).ToList();
                var next = Config with { Bindings = bindings, DictationTested = false };
                Store.Save(next); Config = next; learning = null; SynchronizeRoute(true);
                Status = $"Learned {Config.Bindings[index].Name}: {usage}"; Changed?.Invoke(); return;
            }
            if(MicrophoneTesting||ButtonTesting||MaySendOutput?.Invoke()==false||repeatedDown)return;
            SynchronizeRoute();
            var route=routedConfig;
            var source=Config.Bindings.FirstOrDefault(binding=>binding.Usage==usage);
            if(source?.ControlID is string controlID&&VoiceTypingRouting.ShouldTrigger(Config,route!=null&&output.IsTargetFrontmost(route)?route:null,controlID,down,false,false))
            {
                if(ClaimVoice?.Invoke()==false)throw new InvalidOperationException("Another remote is dictating. Stop it first.");
                try{if(TargetOutput.Foreground()==null)throw new InvalidOperationException("Focus a text field before starting Windows voice typing.");AudioInputs.Check(Config.Microphones.GetValueOrDefault(Config.DevicePluginID));output.TapShortcut("WIN+H");Status="Windows voice typing shortcut sent. Use the Windows voice typing panel to stop listening.";}
                finally{if(!output.HasHeldKeys)ReleaseVoice?.Invoke();}
                Changed?.Invoke();return;
            }
            var match=route?.Bindings.FirstOrDefault(binding=>binding.Usage==usage);
            if(match==null||route==null||(match.Action!=ActionKind.Focus&&output.Plugin?.Supports(match.Action)!=true))return;
            if(match.Action==ActionKind.Focus&&repeatedDown)return;
            if (match.Action == ActionKind.Dictate)
            {
                if (route.VoiceMode == "hold" && !down) { FinishVoice(); return; }
                if (down && route.VoiceMode == "toggle" && VoiceActive) FinishVoice();
                else if (down && !voice.Held && !pending) BeginVoice(route);
            }
            else if (down && match.Action == ActionKind.Focus)
            {
                FinishVoice();if(VoiceActive)throw new InvalidOperationException("Stop voice input before opening another app.");
                var target=launchCycle.Next(match,Config,route,Catalog.Apps);
                new TargetOutput{Plugin=Catalog.Find(target.AppPluginID,"app").App}.Show(target);
                Status="Opening "+Catalog.Find(target.AppPluginID,"app").Name;Changed?.Invoke();
            }
            else if (down && match.Action != ActionKind.Native)
            {
                if (!output.IsTargetFrontmost(route)) throw new InvalidOperationException("Switch to the selected app before using mapped typing buttons.");
                output.Tap(match.Action);
                if(match.Action==ActionKind.Backspace){repeatUsage=usage;repeatRoute=route;repeatAfter=DateTime.UtcNow.AddMilliseconds(350);repeatTimer.Start();}
            }
        }
        catch (Exception error) { Status = error.Message; Changed?.Invoke(); }
    }
    private async void BeginVoice(Configuration route)
    {
        try
        {
            if(MicrophoneTesting)throw new InvalidOperationException("Close Microphone test before starting dictation.");
            AudioInputs.Check(Config.Microphones.GetValueOrDefault(Config.DevicePluginID));
            if (output.Plugin?.Supports(ActionKind.Dictate) != true) throw new InvalidOperationException("This app plugin does not provide dictation.");
            if (!route.ShortcutConfirmed) throw new InvalidOperationException("Match the shortcut to the selected app’s hold-to-dictate setting and check Confirmed.");
            TargetOutput.ParseShortcut(route.Shortcut);
            if(route.FollowActiveApp){if(!output.IsTargetFrontmost(route))throw new InvalidOperationException("The active app changed. Press the remote button again in your app.");}
            else output.Show(route);
            if(ClaimVoice?.Invoke()==false)throw new InvalidOperationException("Another remote is dictating. Stop it first.");
            int ticket = voiceStart.Begin();
            await Task.Delay(250);
            SynchronizeRoute();
            if (!voiceStart.TryComplete(ticket,Running)) return;
            if (!output.IsTargetFrontmost(route)) throw new InvalidOperationException("The selected app is not in front. Open it and try again.");
            if(MicrophoneTesting)return;
            AudioInputs.Check(Config.Microphones.GetValueOrDefault(Config.DevicePluginID));
            output.Hold(route.Shortcut); voice.Commit(true, DateTimeOffset.UtcNow);
            Status = "Dictation shortcut held · "+MicrophoneSummary;
        }
        catch (Exception error) { voiceStart.Cancel();if(!output.HasHeldKeys)ReleaseVoice?.Invoke();Status = error.Message; }
        Changed?.Invoke();
    }
    public void Dispose(){Stop();timer.Dispose();repeatTimer.Dispose();}
    private void FinishVoice()
    {
        bool wasActive=VoiceActive;
        repeatTimer.Stop();repeatUsage=null;
        voiceStart.Cancel();
        try { output.Release(); voice.Commit(false, DateTimeOffset.UtcNow);ReleaseVoice?.Invoke();if(wasActive)Status = "Dictation shortcut released"; }
        catch (Exception error) { Status = error.Message; }
        Changed?.Invoke();
    }
}
