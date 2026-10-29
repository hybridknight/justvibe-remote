using JustVibeRemote.Core;
if (args.Length != 2 || args[0] != "validate")
{
    Console.Error.WriteLine("Usage: dotnet run --project windows/JustVibeRemote.PluginTool -- validate <plugin-folder-or-plugin.json>");
    return 2;
}
try
{
    var path = Directory.Exists(args[1]) ? Path.Combine(args[1], "plugin.json") : args[1];
    if (new FileInfo(path).Length > 65_536) throw new InvalidDataException("Manifest exceeds 64 KiB");
    var plugin = PluginManifest.Decode(File.ReadAllBytes(path));
    Console.WriteLine($"Valid API v{plugin.ApiVersion} {plugin.Kind} plugin: {plugin.Id} {plugin.Version} ({string.Join(", ", plugin.Platforms)})");
    return 0;
}
catch (Exception error) { Console.Error.WriteLine(error.Message); return 1; }
