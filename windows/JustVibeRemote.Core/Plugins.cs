using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace JustVibeRemote.Core;

public sealed record PluginTarget
{
    public string[] BundleIds { get; init; } = [];
    public string[] Names { get; init; } = [];
}
public sealed record PluginAction
{
    public string Operation { get; init; } = "";
    public Dictionary<string, string>? Shortcuts { get; init; }
}
public sealed record DevicePlugin
{
    public string Adapter { get; init; } = "";
    public DeviceProfile Profile { get; init; } = new();
    public RemoteLayout? Layout { get; init; }
}
public sealed record AppPlugin
{
    public string Adapter { get; init; } = "";
    public Dictionary<string, PluginTarget> Targets { get; init; } = [];
    public Dictionary<string, PluginAction> Actions { get; init; } = [];
    public bool Supports(ActionKind action) => action == ActionKind.Native || Actions.ContainsKey(action.ToString().ToLowerInvariant());
    public string Shortcut(ActionKind action, string platform = "windows") =>
        Actions.GetValueOrDefault(action.ToString().ToLowerInvariant())?.Shortcuts?.GetValueOrDefault(platform)
        ?? throw new InvalidDataException("The selected app plugin does not provide this shortcut.");
}
public sealed record PluginManifest
{
    public int SchemaVersion { get; init; }
    public int ApiVersion { get; init; }
    public string Id { get; init; } = "";
    public string Version { get; init; } = "";
    public string Name { get; init; } = "";
    public string Author { get; init; } = "";
    public string Kind { get; init; } = "";
    public string[] Platforms { get; init; } = [];
    public string[] Capabilities { get; init; } = [];
    public DevicePlugin? Device { get; init; }
    public AppPlugin? App { get; init; }
    public void Validate()
    {
        static void Require(bool value, string message) { if (!value) throw new InvalidDataException(message); }
        Require(SchemaVersion == 1 && ApiVersion == 1 && Device?.Layout == null || SchemaVersion == 2 && ApiVersion == 2 && Kind == "device" && Device?.Layout != null || SchemaVersion==3 && ApiVersion==3 && Kind=="app" && Platforms.SequenceEqual(new[]{"macos"}), "Unsupported plugin schema or host API version");
        Require(Id.Length <= 150 && Regex.IsMatch(Id, @"^[a-z][a-z0-9]*(?:[.-][a-z0-9]+)+$"), "Invalid plugin ID");
        Require(Version.Length <= 64 && Regex.IsMatch(Version, @"^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$"), "Invalid plugin version");
        Require(!string.IsNullOrWhiteSpace(Name) && Name.Length <= 100 && Author.Length is > 0 and <= 150, "Plugin name and author are required");
        Require(Platforms.Length > 0 && Platforms.All(p => p is "macos" or "windows") && Platforms.Distinct().Count() == Platforms.Length, "Invalid plugin platforms");
        if (Kind == "device")
        {
            Require(Device?.Adapter == "hid.standard" && App == null, "Invalid device adapter or mixed plugin kinds");
            Require(Capabilities.Distinct().Count() == Capabilities.Length && Capabilities.ToHashSet().SetEquals(Device!.Profile.Audio == "none" ? ["hid.standard"] : ["hid.standard", "audio.native-input"]), "Unsupported device capabilities");
            Device!.Profile.Validate(); Device.Layout?.Validate();
        }
        else if (Kind == "app")
        {
            Require(App?.Adapter == "shortcuts" && Device == null, "Invalid app adapter or mixed plugin kinds");
            Require(Capabilities.Distinct().Count() == Capabilities.Length && Capabilities.ToHashSet().SetEquals(["target.focus", "input.shortcuts"]), "Unsupported app capabilities");
            Require(App!.Targets.Keys.All(p => p is "macos" or "windows"), "Unknown target platform");
            foreach (var platform in Platforms)
            {
                Require(App.Targets.ContainsKey(platform), "Missing target platform");
                var target = App.Targets[platform];
                Require(target.Names.Length > 0 || platform == "macos" && target.BundleIds.Length > 0, "Target identities are required");
                Require(target.Names.Concat(target.BundleIds).All(n => n.Length is > 0 and <= 150 && !n.Contains('/') && !n.Contains('\\')), "Target identities must be names, not paths");
            }
            Require(App.Actions.GetValueOrDefault("focus")?.Operation == "focus", "App plugins must provide focus");
            foreach (var (key, action) in App.Actions)
            {
                Require(Enum.TryParse<ActionKind>(key, true, out var intent) && intent != ActionKind.Native && key == intent.ToString().ToLowerInvariant(), "Unknown app action");
                var expected = intent == ActionKind.Focus ? "focus" : intent == ActionKind.Dictate ? "hold-shortcut" : "tap-shortcut";
                var toggle=intent==ActionKind.Dictate && action.Operation=="toggle-shortcut" && SchemaVersion==3 && ApiVersion==3 && Platforms.SequenceEqual(new[]{"macos"});
                Require(action.Operation == expected || toggle, "Unsupported action operation");
                if (intent == ActionKind.Focus) Require(action.Shortcuts == null, "Focus cannot execute a shortcut");
                else
                {
                    Require(action.Shortcuts != null && action.Shortcuts.Keys.All(Platforms.Contains), "Unknown shortcut platform");
                    foreach (var platform in Platforms)
                    {
                        Require(action.Shortcuts!.ContainsKey(platform), "Missing action shortcut");
                        ValidateShortcut(action.Shortcuts[platform], platform);
                    }
                }
            }
        }
        else throw new InvalidDataException("Unknown plugin kind");
    }
    public static void ValidateShortcut(string shortcut, string platform)
    {
        var tokens = shortcut.ToUpperInvariant().Split('+', StringSplitOptions.TrimEntries);
        HashSet<string> allowed = ["CTRL", "CONTROL", "SHIFT", "ALT", "SPACE", "RETURN", "ENTER", "ESC", "BACKSPACE"];
        allowed.UnionWith(platform == "macos" ? ["OPTION", "CMD", "COMMAND"] : ["RALT", "WIN"]);
        if (tokens.Length is < 1 or > 5 || !tokens.All(t => allowed.Contains(t) || Regex.IsMatch(t, "^[A-Z]$")))
            throw new InvalidDataException("Unsupported shortcut in plugin");
        if (platform == "macos" &&
            (!new[] { "SPACE", "RETURN", "ENTER", "ESC", "BACKSPACE" }.Contains(tokens[^1]) && tokens[^1].Length != 1 ||
             !tokens.SkipLast(1).All(t => new[] { "CTRL", "CONTROL", "SHIFT", "ALT", "OPTION", "CMD", "COMMAND" }.Contains(t))))
            throw new InvalidDataException("macOS shortcuts require modifiers followed by one key");
    }
    public static PluginManifest Decode(byte[] bytes)
    {
        if (bytes.Length > 65_536) throw new InvalidDataException("Manifest exceeds 64 KiB");
        var options = new JsonSerializerOptions(ConfigurationStore.Json) { UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow, MaxDepth = 32, PropertyNameCaseInsensitive = false };
        using (var document = JsonDocument.Parse(bytes, new JsonDocumentOptions { MaxDepth = 32 }))
        {
            if (document.RootElement.TryGetProperty("device", out var device) && device.ValueKind == JsonValueKind.Object && device.TryGetProperty("layout", out var layout) && layout.ValueKind == JsonValueKind.Object && layout.TryGetProperty("buttons", out var controls) && controls.ValueKind == JsonValueKind.Array)
                foreach (var control in controls.EnumerateArray())
                    if (control.TryGetProperty("defaultAction", out var action) && (action.ValueKind != JsonValueKind.String || !Enum.TryParse<ActionKind>(action.GetString(), true, out var intent) || action.GetString() != intent.ToString().ToLowerInvariant()))
                        throw new InvalidDataException("Layout defaultAction must be a supported lowercase action name");
        }
        var manifest = JsonSerializer.Deserialize<PluginManifest>(bytes, options) ?? throw new InvalidDataException("Empty plugin manifest");
        manifest.Validate(); return manifest;
    }
}
public sealed class PluginCatalog
{
    public List<PluginManifest> Plugins { get; } = [];
    public List<string> Diagnostics { get; } = [];
    public IEnumerable<PluginManifest> Devices => Plugins.Where(p => p.Kind == "device");
    public IEnumerable<PluginManifest> Apps => Plugins.Where(p => p.Kind == "app");
    public PluginManifest Find(string id, string kind) => Plugins.FirstOrDefault(p => p.Id == id && p.Kind == kind)
        ?? throw new InvalidDataException($"Selected {kind} plugin is missing or invalid. Choose an installed plugin and save settings.");
    public PluginCatalog(string bundled, string user, string platform = "windows")
    {
        List<PluginManifest> Scan(string root)
        {
            var result = new List<PluginManifest>();
            if (!Directory.Exists(root)) return result;
            string[] directories;
            try { directories = Directory.GetDirectories(root); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { Diagnostics.Add($"Cannot read plugin directory: {error.Message}"); return result; }
            foreach (var directory in directories.Order(StringComparer.Ordinal))
            {
                if (Path.GetFileName(directory).StartsWith('.')) continue;
                try
                {
                    if ((File.GetAttributes(directory) & FileAttributes.ReparsePoint) != 0) continue;
                    var manifestPath = Path.Combine(directory, "plugin.json");
                    var info = new FileInfo(manifestPath);
                    if ((info.Attributes & FileAttributes.ReparsePoint) != 0 || info.Length > 65_536) throw new InvalidDataException("Manifest is a symlink or exceeds 64 KiB");
                    var plugin = PluginManifest.Decode(File.ReadAllBytes(manifestPath));
                    if (plugin.Platforms.Contains(platform)) result.Add(plugin);
                }
                catch (Exception error) { Diagnostics.Add($"{Path.GetFileName(directory)}: {error.Message}"); }
            }
            return result;
        }
        var builtins = Scan(bundled); var users = Scan(user); var reserved = builtins.Select(p => p.Id).ToHashSet();
        foreach (var group in builtins.GroupBy(p => p.Id))
            if (group.Count() == 1) Plugins.Add(group.Single()); else Diagnostics.Add($"Duplicate bundled plugin ID: {group.Key}");
        foreach (var group in users.GroupBy(p => p.Id))
            if (reserved.Contains(group.Key)) Diagnostics.Add($"User plugin cannot override bundled ID: {group.Key}");
            else if (group.Count() != 1) Diagnostics.Add($"Duplicate user plugin ID disabled: {group.Key}");
            else Plugins.Add(group.Single());
        Plugins.Sort((a, b) => string.CompareOrdinal(a.Id, b.Id));
    }
}

public static class PluginSelection
{
    public static Configuration Select(Configuration config, PluginCatalog catalog, string deviceID, string appID)
    {
        var device = catalog.Find(deviceID, "device"); var app = catalog.Find(appID, "app");
        var sets = new Dictionary<string, List<Binding>>(config.BindingSets) { [config.DevicePluginID + "|" + config.AppPluginID] = config.Bindings.ToList() };
        bool different = deviceID != config.DevicePluginID || appID != config.AppPluginID;
        var bindings = different ? sets.GetValueOrDefault(deviceID + "|" + appID)?.ToList() ?? device.Device!.Layout?.Bindings() ?? new Configuration().Bindings : config.Bindings.ToList();
        var next = config with { DevicePluginID = deviceID, AppPluginID = appID, Profile = device.Device!.Profile, BindingSets = sets, Bindings = bindings };
        var mappings=new Dictionary<string,AppMapping>(config.AppMappings){[AppRouting.Key(config.DevicePluginID,config.AppPluginID)]=AppMapping.From(config)};
        next=next with{AppMappings=mappings};
        if(different)
        {
            if(mappings.TryGetValue(AppRouting.Key(deviceID,appID),out var saved))next=saved.Apply(next);
            else
            {
                next=next with{Shortcut=app.App!.Supports(ActionKind.Dictate)?app.App.Shortcut(ActionKind.Dictate):"",ShortcutConfirmed=false,TargetAppPath="",DictationTested=false,VoiceMode="toggle"};
                if(deviceID==config.DevicePluginID&&!config.BindingSets.ContainsKey(AppRouting.Key(deviceID,appID)))next=next with{Bindings=next.Bindings.Select(b=>b with{Usage=config.Bindings.FirstOrDefault(old=>b.ControlID!=null?(old.ControlID==b.ControlID||(old.ControlID==null&&old.Name==b.Name)):old.Name==b.Name)?.Usage}).ToList()};
            }
        }
        if(device.Device!.Layout!=null)next=next with{Bindings=device.Device.Layout.Bindings(next.Bindings)};
        next=next with{Bindings=next.Bindings.Select(b=>app.App!.Supports(b.Action)?b:b with{Action=ActionKind.Native}).ToList()};
        return next;
    }
}
