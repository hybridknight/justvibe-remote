namespace JustVibeRemote.Core;

public sealed record AppMapping(List<Binding> Bindings,string Shortcut,bool ShortcutConfirmed,string VoiceMode,string TargetAppPath,bool DictationTested)
{
    public static AppMapping From(Configuration c)=>new(c.Bindings.ToList(),c.Shortcut,c.ShortcutConfirmed,c.VoiceMode,c.TargetAppPath,c.DictationTested);
    public Configuration Apply(Configuration c)=>c with{Bindings=Bindings.ToList(),Shortcut=Shortcut,ShortcutConfirmed=ShortcutConfirmed,VoiceMode=VoiceMode,TargetAppPath=TargetAppPath,DictationTested=DictationTested};
}
public static class SharedActions
{
    public static bool Supports(ActionKind action)=>action is ActionKind.Native or ActionKind.Focus or ActionKind.Send or ActionKind.Backspace or ActionKind.Escape;
    public static AppPlugin Plugin=>new(){Adapter="shortcuts",Actions=new(){["focus"]=new(){Operation="focus"},["send"]=new(){Operation="tap-shortcut",Shortcuts=new(){["windows"]="ENTER"}},["backspace"]=new(){Operation="tap-shortcut",Shortcuts=new(){["windows"]="BACKSPACE"}},["escape"]=new(){Operation="tap-shortcut",Shortcuts=new(){["windows"]="ESC"}}}};
}
public sealed record ForegroundApp(string BundleID="",string Name="",string Path="",string Instance="");
public static class AppRouting
{
    public static string Key(string deviceID,string appID)=>deviceID+"|"+appID;
    public static Configuration LaunchTarget(Binding binding,Configuration config,Configuration route,IEnumerable<PluginManifest> apps)
    {
        string id=binding.LaunchAppID??route.AppPluginID;
        if(binding.Action!=ActionKind.Focus||id==Configuration.NoSpecificAppID||!apps.Any(p=>p.Id==id&&p.Kind=="app"))throw new InvalidDataException("Choose an app for this button's Open app action. Its app profile may have been removed.");
        string path=binding.LaunchAppPath??(id==config.AppPluginID?config.TargetAppPath:id==route.AppPluginID?route.TargetAppPath:config.AppMappings.GetValueOrDefault(Key(config.DevicePluginID,id))?.TargetAppPath??"");
        return route with{AppPluginID=id,TargetAppPath=path,TargetInstance=""};
    }
    private static bool SamePath(string a,string b,string platform)
    {
        try{return string.Equals(System.IO.Path.GetFullPath(a),System.IO.Path.GetFullPath(b),platform=="windows"?StringComparison.OrdinalIgnoreCase:StringComparison.Ordinal);}
        catch(Exception error) when(error is ArgumentException or NotSupportedException or System.IO.PathTooLongException){return false;}
    }
    public static Configuration? Resolve(Configuration config,IEnumerable<PluginManifest> apps,ForegroundApp? foreground,string platform="windows")
    {
        if(!config.FollowActiveApp&&config.AppPluginID!=Configuration.NoSpecificAppID)return config;
        if(foreground==null)return null;
        Configuration? Shared()
        {
            var shared=config;
            if(config.AppPluginID!=Configuration.NoSpecificAppID)
            {
                if(config.AppMappings.TryGetValue(Key(config.DevicePluginID,Configuration.NoSpecificAppID),out var saved))shared=saved.Apply(shared);
                else if(config.BindingSets.TryGetValue(Key(config.DevicePluginID,Configuration.NoSpecificAppID),out var savedBindings))shared=shared with{Bindings=savedBindings};
                else return null;
            }
            return shared with{AppPluginID=Configuration.NoSpecificAppID,TargetAppPath=foreground.Path,TargetInstance=foreground.Instance,Bindings=shared.Bindings.Select(b=>SharedActions.Supports(b.Action)?b:b with{Action=ActionKind.Native}).ToList()};
        }
        var matches=new List<(int Score,Configuration Config)>();
        foreach(var plugin in apps)
        {
            string key=Key(config.DevicePluginID,plugin.Id);
            if(plugin.Id!=config.AppPluginID&&!config.AppMappings.ContainsKey(key)&&!config.BindingSets.ContainsKey(key))continue;
            var candidate=config with{AppPluginID=plugin.Id};
            if(plugin.Id!=config.AppPluginID)
            {
                if(config.AppMappings.TryGetValue(key,out var saved))candidate=saved.Apply(candidate);
                else candidate=candidate with{Bindings=config.BindingSets[key].ToList(),Shortcut=plugin.App!.Supports(ActionKind.Dictate)?plugin.App.Shortcut(ActionKind.Dictate,platform):"",ShortcutConfirmed=false,TargetAppPath="",DictationTested=false};
            }
            candidate=candidate with{Bindings=candidate.Bindings.Select(b=>b.Action==ActionKind.Focus||plugin.App?.Supports(b.Action)==true?b:b with{Action=ActionKind.Native}).ToList()};
            if(plugin.App?.Targets.GetValueOrDefault(platform) is not {} target)continue;
            int score=0;
            if(candidate.TargetAppPath.Length>0)
            {
                if(foreground.Path.Length>0&&SamePath(candidate.TargetAppPath,foreground.Path,platform))score=3;
            }
            else if(foreground.BundleID.Length>0&&target.BundleIds.Contains(foreground.BundleID))score=2;
            else if(foreground.Name.Length>0&&target.Names.Contains(foreground.Name,platform=="windows"?StringComparer.OrdinalIgnoreCase:StringComparer.Ordinal))score=1;
            if(score>0)matches.Add((score,candidate));
        }
        if(matches.Count==0)return Shared();
        int best=matches.Max(m=>m.Score);var winners=matches.Where(m=>m.Score==best).ToList();
        return winners.Count==1?winners[0].Config:null;
    }
}
