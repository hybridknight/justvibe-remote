using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using JustVibeRemote.Core;

namespace JustVibeRemote;

internal sealed class TargetOutput

{
    public AppPlugin? Plugin { get; set; }
    private readonly List<ushort> held = [];
    public bool HasHeldKeys => held.Count > 0;
    public static ushort[] ParseShortcut(string text)
    {
        var tokens = text.ToUpperInvariant().Split('+', StringSplitOptions.TrimEntries);
        if (tokens.Length == 0 || tokens.Any(string.IsNullOrEmpty)) throw new InvalidDataException("Enter a shortcut such as RALT or CTRL+SHIFT+D.");
        return tokens.Select(token => token switch
        {
            "CTRL" or "CONTROL" => (ushort)0xA2, "SHIFT" => (ushort)0xA0, "ALT" => (ushort)0xA4,
            "RALT" => (ushort)0xA5, "WIN" => (ushort)0x5B, "SPACE" => (ushort)0x20,
            "ENTER" or "RETURN" => (ushort)0x0D, "ESC" => (ushort)0x1B, "BACKSPACE" => (ushort)0x08,
            _ when token.Length == 1 && token[0] is >= 'A' and <= 'Z' => (ushort)token[0],
            _ => throw new InvalidDataException($"Unsupported shortcut key: {token}")
        }).Distinct().ToArray();
    }
    public static ForegroundApp? Foreground()
    {
        try
        {
            GetWindowThreadProcessId(GetForegroundWindow(),out var pid);
            if(pid==0)return null;
            using var process=Process.GetProcessById((int)pid);
            string path="";
            try{path=process.MainModule?.FileName??"";}catch(Win32Exception){}
            return new ForegroundApp(Name:process.ProcessName,Path:path,Instance:pid.ToString());
        }
        catch(Exception error) when(error is Win32Exception or InvalidOperationException or ArgumentException){return null;}
    }
    private Process? FindTarget(Configuration config)
    {
        var names = config.TargetAppPath.Length == 0 ? Plugin?.Targets.GetValueOrDefault("windows")?.Names ?? [] : [Path.GetFileNameWithoutExtension(config.TargetAppPath)];
        Process? found = null;
        foreach (var candidate in names.SelectMany(Process.GetProcessesByName))
        {
            try
            {
                bool pathMatches = config.TargetAppPath.Length == 0 ||
                    string.Equals(candidate.MainModule?.FileName, config.TargetAppPath, StringComparison.OrdinalIgnoreCase);
                if (found == null && pathMatches && candidate.MainWindowHandle != 0) { found = candidate; continue; }
            }
            catch (Exception error) when (error is Win32Exception or InvalidOperationException) { }
            candidate.Dispose();
        }
        return found;
    }
    public static string RunningPath(PluginManifest app)
    {
        try{using var process=new TargetOutput{Plugin=app.App}.FindTarget(new Configuration{AppPluginID=app.Id});return process?.MainModule?.FileName??"";}
        catch(Exception error) when(error is Win32Exception or InvalidOperationException){return "";}
    }
    public bool IsTargetFrontmost(Configuration config)
    {
        var front=Foreground();
        if(front==null)return false;
        if(config.AppPluginID==Configuration.NoSpecificAppID)return config.TargetInstance.Length>0&&config.TargetInstance==front.Instance;
        if(config.TargetAppPath.Length>0)return front.Path.Length>0&&string.Equals(front.Path,config.TargetAppPath,StringComparison.OrdinalIgnoreCase);
        return Plugin?.Targets.GetValueOrDefault("windows")?.Names.Contains(front.Name,StringComparer.OrdinalIgnoreCase)==true;
    }
    public void Show(Configuration config)
    {
        if(IsTargetFrontmost(config))return;
        using var process = FindTarget(config);
        if (process != null)
        {
            ShowWindow(process.MainWindowHandle, 9);
            SetForegroundWindow(process.MainWindowHandle);
        }
        else if (config.TargetAppPath.Length > 0)
        {
            Process.Start(new ProcessStartInfo(config.TargetAppPath) { UseShellExecute = false });
        }
        else throw new InvalidOperationException("Open the selected app first, or choose its application in JustVibe Remote.");
    }
    public void Hold(string shortcut)
    {
        if (held.Count > 0) throw new InvalidOperationException("Release the previous shortcut with Stop before starting another session.");
        var keys = ParseShortcut(shortcut);
        if (keys.Any(key => (GetAsyncKeyState(key) & 0x8000) != 0))
            throw new InvalidOperationException("Release the shortcut keys on your keyboard, then try again.");
        try
        {
            foreach (var key in keys) { held.Add(key); Post(key, false); }
        }
        catch { try { Release(); } catch { /* Retain failed keys for Stop to retry. */ } throw; }
    }
    public void Release()
    {
        Exception? failure = null;
        foreach (var key in held.ToArray().Reverse())
        {
            try { Post(key, true); held.Remove(key); }
            catch (Exception error) { failure ??= error; }
        }
        if (failure != null) throw failure;
    }
    public void TapShortcut(string shortcut){Hold(shortcut);Release();}
    public void Tap(ActionKind action)
    {
        if (Plugin == null) throw new InvalidOperationException("Select an app plugin first");
        Hold(Plugin.Shortcut(action));
        Release();
    }
    private static void Post(ushort key, bool up)
    {
        uint mapped = MapVirtualKey(key, 4);
        if (mapped == 0) throw new InvalidOperationException("Windows cannot map this shortcut key.");
        var input = new Input { Type = 1, Data = new InputData { Keyboard = new KeyInput {
            Scan = (ushort)(mapped & 0xFF), Flags = 8u | (up ? 2u : 0u) | ((mapped & 0xFF00) == 0xE000 ? 1u : 0u), Extra = (nuint)0x52564942
        } } };
        if (SendInput(1, [input], Marshal.SizeOf<Input>()) != 1)
            throw new Win32Exception(Marshal.GetLastWin32Error(), "Windows blocked the shortcut. Keep the target app and JustVibe Remote at the same permission level.");
    }
    [StructLayout(LayoutKind.Sequential)] private struct Input { public uint Type; public InputData Data; }
    [StructLayout(LayoutKind.Explicit)] private struct InputData { [FieldOffset(0)] public KeyInput Keyboard; [FieldOffset(0)] public MouseInput Mouse; }
    [StructLayout(LayoutKind.Sequential)] private struct KeyInput { public ushort Key, Scan; public uint Flags, Time; public nuint Extra; }
    [StructLayout(LayoutKind.Sequential)] private struct MouseInput { public int X, Y; public uint Data, Flags, Time; public nuint Extra; }
    [DllImport("user32.dll", SetLastError = true)] private static extern uint SendInput(uint count, Input[] inputs, int size);
    [DllImport("user32.dll")] private static extern uint MapVirtualKey(uint code, uint type);
    [DllImport("user32.dll")] private static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] private static extern nint GetForegroundWindow();
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(nint window, out uint pid);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(nint window);
    [DllImport("user32.dll")] private static extern bool ShowWindow(nint window, int command);
}
