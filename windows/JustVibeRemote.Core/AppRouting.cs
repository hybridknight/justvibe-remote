namespace JustVibeRemote.Core;

public sealed record AppMapping(List<Binding> Bindings,string Shortcut,bool ShortcutConfirmed,string VoiceMode,string TargetAppPath,bool DictationTested)
{
    public static AppMapping From(Configuration c)=>new(c.Bindings.ToList(),c.Shortcut,c.ShortcutConfirmed,c.VoiceMode,c.TargetAppPath,c.DictationTested);
    public Configuration Apply(Configuration c)=>c with{Bindings=Bindings.ToList(),Shortcut=Shortcut,ShortcutConfirmed=ShortcutConfirmed,VoiceMode=VoiceMode,TargetAppPath=TargetAppPath,DictationTested=DictationTested};
}
public sealed record ForegroundApp(string BundleID="",string Name="",string Path="",string Instance="");
public static class AppRouting
{
    public static string Key(string deviceID,string appID)=>deviceID+"|"+appID;
    private static bool SamePath(string a,string b,string platform)
    {
        try{return string.Equals(System.IO.Path.GetFullPath(a),System.IO.Path.GetFullPath(b),platform=="windows"?StringComparison.OrdinalIgnoreCase:StringComparison.Ordinal);}
        catch(Exception error) when(error is ArgumentException or NotSupportedException or System.IO.PathTooLongException){return false;}
    }
    public static Configuration? Resolve(Configuration config,IEnumerable<PluginManifest> apps,ForegroundApp? foreground,string platform="windows")
    {
        if(!config.FollowActiveApp)return config;
        if(foreground==null)return null;
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
            candidate=candidate with{Bindings=candidate.Bindings.Select(b=>plugin.App?.Supports(b.Action)==true?b:b with{Action=ActionKind.Native}).ToList()};
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
        if(matches.Count==0)return null;
        int best=matches.Max(m=>m.Score);var winners=matches.Where(m=>m.Score==best).ToList();
        return winners.Count==1?winners[0].Config:null;
    }
}
