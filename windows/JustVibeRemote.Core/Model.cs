using System.Text.Json;
using System.Text.Json.Serialization;

namespace JustVibeRemote.Core;

public sealed record DeviceProfile
{
    public int SchemaVersion { get; init; } = 1;
    public string Id { get; init; } = "unselected";
    public string Name { get; init; } = "No device plugin selected";
    public int VendorId { get; init; }
    public int ProductId { get; init; }
    public string Audio { get; init; } = "native-usb-microphone";
    public int ConsumerReportId { get; init; } = 2;
    public int ConsumerReportLength { get; init; } = 3;
    public int ConsumerUsageOffset { get; init; } = 1;
    [JsonIgnore] public string HardwareId => $"{VendorId:X4}:{ProductId:X4}";
    public void Validate()
    {
        if (SchemaVersion != 1 || VendorId is < 1 or > 65535 || ProductId is < 1 or > 65535 ||
            Audio is not ("native-usb-microphone" or "none") || ConsumerReportLength is < 3 or > 64 ||
            ConsumerUsageOffset < 1 || ConsumerUsageOffset + 2 > ConsumerReportLength || ConsumerReportId is < 1 or > 255)
            throw new InvalidDataException("Invalid or unsupported device profile. Use an explicit HID hardware identity and a supported fallback report layout. Microphone support is optional.");
    }
}
public readonly record struct Usage(uint Page, uint Code)
{
    [JsonIgnore] public bool IsButton => Page == 7 && Code is >= 4 and < 0xE0 || Page == 12 && Code > 0 || Page == 1 && Code is >= 0x81 and <= 0x83;
    public override string ToString() => $"{Page:X4}:{Code:X4}";
}
[JsonConverter(typeof(JsonStringEnumConverter<ActionKind>))]
public enum ActionKind { Native, Dictate, Focus, Send, Backspace, Escape }
public sealed record Binding(string Name, Usage? Usage, ActionKind Action, string? ControlID = null);
public sealed record Configuration
{
    public int SchemaVersion { get; init; } = 1;
    public DeviceProfile Profile { get; init; } = new();
    public string DevicePluginID { get; init; } = "org.justviberemote.device.xingwei-usb";
    public string AppPluginID { get; init; } = "org.justviberemote.app.chatgpt";
    public List<Binding> Bindings { get; init; } =
    [new("Microphone", null, ActionKind.Dictate), new("Power", null, ActionKind.Native),
     new("OK", new(7, 0x28), ActionKind.Native), new("Back", new(12, 0x224), ActionKind.Native),
     new("Home", new(12, 0x223), ActionKind.Native), new("Menu", new(7, 0x65), ActionKind.Native)];
    public Dictionary<string, List<Binding>> BindingSets { get; init; } = [];
    public Dictionary<string, AppMapping> AppMappings { get; init; } = [];
    public bool FollowActiveApp { get; init; }
    public Dictionary<string,MicrophonePreference> Microphones { get; init; } = [];
    public string VoiceMode { get; init; } = "toggle";
    public string Shortcut { get; init; } = "";
    public bool ShortcutConfirmed { get; init; }
    public bool DictationTested { get; init; }
    public bool AutoConnect { get; init; }
    public string TargetAppPath { get; init; } = "";
    public Configuration MigrateLegacyAppNamespace()
    {
        const string legacy="org.justviberemote.app.codex",current="org.justviberemote.app.chatgpt";
        Dictionary<string,T> Migrate<T>(Dictionary<string,T> source)
        {
            var result=new Dictionary<string,T>(source);
            foreach(var key in source.Keys.Where(k=>k.EndsWith("|"+legacy,StringComparison.Ordinal)))
            {
                var replacement=key[..^legacy.Length]+current;
                result.TryAdd(replacement,source[key]);result.Remove(key);
            }
            return result;
        }
        var result=this with {AppPluginID=AppPluginID==legacy ? current:AppPluginID,BindingSets=Migrate(BindingSets),AppMappings=Migrate(AppMappings)};
        if(AppPluginID==legacy)
        {
            var currentKey=DevicePluginID+"|"+current;
            if(AppMappings.TryGetValue(currentKey,out var saved))result=saved.Apply(result);
            else if(BindingSets.TryGetValue(currentKey,out var bindings))result=result with{Bindings=bindings};
        }
        return result;
    }
    public void Validate()
    {
        Profile.Validate();
        if (SchemaVersion != 1 || VoiceMode is not ("hold" or "toggle") || Bindings.Count is < 1 or > 64 ||
            Bindings.Any(binding => !Enum.IsDefined(binding.Action)) || AppMappings.Count>256 ||
            AppMappings.Values.Any(m=>m.Bindings.Count is <1 or >64||m.VoiceMode is not ("hold" or "toggle")||m.Bindings.Any(b=>!Enum.IsDefined(b.Action)))||
            BindingSets.Values.Any(b=>b.Count is <1 or >64))
            throw new InvalidDataException("Unsupported settings. The original file has been preserved.");
    }
}
public sealed class ConfigurationStore(string path)
{
    public string Path { get; } = path;
    public static JsonSerializerOptions Json { get; } = new() { PropertyNamingPolicy = JsonNamingPolicy.CamelCase, PropertyNameCaseInsensitive = true, WriteIndented = true };
    public Configuration Load(Configuration? defaults = null)
    {
        if (!File.Exists(Path)) return (defaults ?? new()).MigrateLegacyAppNamespace();
        var result = JsonSerializer.Deserialize<Configuration>(File.ReadAllBytes(Path), Json) ?? throw new InvalidDataException("Empty settings file.");
        result.Validate();
        return result.MigrateLegacyAppNamespace();
    }
    public void Save(Configuration configuration)
    {
        configuration.Validate();
        Directory.CreateDirectory(System.IO.Path.GetDirectoryName(Path)!);
        var temporary = Path + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(configuration, Json));
        File.Move(temporary, Path, true);
    }
}
public sealed class VoiceSession
{
    public bool Held { get; private set; }
    public DateTimeOffset StartedAt { get; private set; }
    public bool? DesiredState(bool down, string mode) => mode == "toggle" ? down ? !Held : null : down == Held ? null : down;
    public void Commit(bool active, DateTimeOffset now) { Held = active; if (active) StartedAt = now; }
    public bool Expired(DateTimeOffset now) => Held && now - StartedAt >= TimeSpan.FromMinutes(2);
}
