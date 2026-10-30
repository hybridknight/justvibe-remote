using JustVibeRemote.Core;
namespace JustVibeRemote;

internal sealed class RemoteSessions:IDisposable
{
    private readonly string root;
    private readonly RemoteSessionOwnership ownership=new();
    private readonly Configuration legacy;
    public PluginCatalog Catalog { get; private set; }
    public string PluginDirectory=>Path.Combine(root,"plugins");
    public Dictionary<string,RemoteController> Controllers { get; }=[];
    public event Action? Changed;
    public RemoteController? Initial=>Controllers.GetValueOrDefault(legacy.DevicePluginID)??Controllers.Values.FirstOrDefault();
    public RemoteSessions(string? directory=null)
    {
        root=directory??Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),"JustVibeRemote");
        Catalog=new(Path.Combine(AppContext.BaseDirectory,"plugins"),PluginDirectory);
        var defaults=new Configuration();
        var device=Catalog.Devices.FirstOrDefault(d=>d.Id==defaults.DevicePluginID)??Catalog.Devices.FirstOrDefault();
        if(device!=null)defaults=defaults with{Profile=device.Device!.Profile,DevicePluginID=device.Id};
        legacy=new ConfigurationStore(Path.Combine(root,"settings.json")).Load(defaults);
        LoadControllers();
    }
    private void LoadControllers()
    {
        var library=new RemoteConfigurationLibrary(root,legacy,Catalog);
        foreach(var device in Catalog.Devices.Where(d=>!Controllers.ContainsKey(d.Id)))
        {
            var controller=new RemoteController(library.StoreFor(device.Id),library.Load(device.Id),PluginDirectory);
            controller.ValidateStart=()=>ownership.Start(device.Id,controller.Config.Profile.HardwareId);
            controller.Stopped=()=>ownership.Stop(device.Id);
            controller.ClaimVoice=()=>ownership.ClaimVoice(device.Id);
            controller.ReleaseVoice=()=>ownership.ReleaseVoice(device.Id);
            controller.MaySendOutput=()=>ownership.AllowsOutput(device.Id);
            controller.Changed+=()=>Changed?.Invoke();Controllers.Add(device.Id,controller);
        }
    }
    public void Activate(){foreach(var controller in Controllers.Values)controller.ResumeIfConfigured();}
    public void StopVoices(){foreach(var controller in Controllers.Values)controller.StopVoice();}
    public void Reload()
    {
        foreach(var controller in Controllers.Values)controller.Stop();
        Catalog=new(Path.Combine(AppContext.BaseDirectory,"plugins"),PluginDirectory);
        foreach(var id in Controllers.Keys.Where(id=>!Catalog.Devices.Any(d=>d.Id==id)).ToArray()){Controllers[id].Dispose();Controllers.Remove(id);}
        foreach(var controller in Controllers.Values)controller.ReloadPlugins();
        LoadControllers();Changed?.Invoke();
    }
    public PluginManifest AddApp(string path,string? shortcut=null)
    {
        var app=LocalAppRegistration.Install(path,shortcut,PluginDirectory,Catalog);
        Catalog=new(Path.Combine(AppContext.BaseDirectory,"plugins"),PluginDirectory);
        foreach(var controller in Controllers.Values)controller.RefreshCatalog();
        Changed?.Invoke();return app;
    }
    public void Dispose(){foreach(var controller in Controllers.Values)controller.Dispose();}
}
