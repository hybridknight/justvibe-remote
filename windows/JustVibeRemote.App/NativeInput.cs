using System.Runtime.InteropServices;
using System.Text;
using JustVibeRemote.Core;

namespace JustVibeRemote;

internal sealed class NativeInput : IDisposable
{
    private readonly DeviceProfile profile;
    private readonly ReceiverDecoder decoder;
    private readonly HashSet<nint> receivers = [];
    private readonly Dictionary<nint, HidReportReader?> reportReaders = [];
    public event Action<Usage, bool>? Edge;
    public event Action? Disconnected;
    public event Action<int>? DevicesChanged;
    public event Action<string>? Error;
    public NativeInput(DeviceProfile profile)
    {
        profile.Validate(); this.profile = profile; decoder = new(profile);
        hub??=new InputWindow();listeners.Add(this);
        RefreshDevices();
    }
    public void RefreshDevices()
    {
        uint count = 0;
        if (GetRawInputDeviceList(null, ref count, (uint)Marshal.SizeOf<DeviceEntry>()) == uint.MaxValue) return;
        if (count > 4096) return;
        var list = new DeviceEntry[count];
        if (GetRawInputDeviceList(list, ref count, (uint)Marshal.SizeOf<DeviceEntry>()) == uint.MaxValue) return;
        var current = list.Take((int)count).Where(item => Matches(item.Device)).Select(item => item.Device).ToHashSet();
        bool removed = receivers.Except(current).Any();
        foreach (var device in receivers.Except(current).ToArray()) RemoveReader(device);
        receivers.Clear(); receivers.UnionWith(current);
        if (removed) { decoder.Clear(); Disconnected?.Invoke(); }
        DevicesChanged?.Invoke(receivers.Count);
    }
    // Raw Input permits one target window per usage in a process. All receivers share it.
    private static readonly List<NativeInput> listeners=[];
    private static InputWindow? hub;
    private sealed class InputWindow:NativeWindow,IDisposable
    {
        public InputWindow()
        {
            CreateHandle(new CreateParams{Caption="JustVibeRemote.Input",Parent=new nint(-3)});
            RawDevice[] registrations=[new(1,6,0x100|0x2000,Handle),new(12,1,0x100|0x2000,Handle),new(1,0x80,0x100|0x2000,Handle)];
            if(!RegisterRawInputDevices(registrations,(uint)registrations.Length,(uint)Marshal.SizeOf<RawDevice>()))
            {DestroyHandle();throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());}
        }
        protected override void WndProc(ref Message message)
        {
            foreach(var listener in listeners.ToArray())
            {
                try
                {
                    if(message.Msg==0xFE)
                    {
                        if(message.WParam==2&&listener.receivers.Remove(message.LParam)){listener.RemoveReader(message.LParam);listener.decoder.Clear();listener.Disconnected?.Invoke();}
                        listener.RefreshDevices();
                    }
                    if(message.Msg==0xFF)listener.Read(message.LParam);
                }
                catch(Exception error){listener.Error?.Invoke(error.Message);}
            }
            base.WndProc(ref message);
        }
        public void Dispose()
        {
            RawDevice[] remove=[new(1,6,1,0),new(12,1,1,0),new(1,0x80,1,0)];
            RegisterRawInputDevices(remove,(uint)remove.Length,(uint)Marshal.SizeOf<RawDevice>());
            DestroyHandle();
        }
    }
    public static string[] Discover()
    {
        uint count=0;
        if(GetRawInputDeviceList(null,ref count,(uint)Marshal.SizeOf<DeviceEntry>())==uint.MaxValue||count>4096)return [];
        var list=new DeviceEntry[count];
        if(GetRawInputDeviceList(list,ref count,(uint)Marshal.SizeOf<DeviceEntry>())==uint.MaxValue)return [];
        return list.Take((int)count).Select(d=>DeviceName(d.Device)).Where(n=>n.Length>0).Distinct().ToArray();
    }
    private void Read(nint token)
    {
        var headerSize = (uint)Marshal.SizeOf<RawHeader>();
        uint length = 0;
        if (GetRawInputData(token, 0x10000003, nint.Zero, ref length, headerSize) == uint.MaxValue || length < headerSize || length > 65536) return;
        var buffer = Marshal.AllocHGlobal((int)length);
        try
        {
            if (GetRawInputData(token, 0x10000003, buffer, ref length, headerSize) == uint.MaxValue) return;
            var header = Marshal.PtrToStructure<RawHeader>(buffer);
            if (!receivers.Contains(header.Device))
            {
                if (!Matches(header.Device)) return;
                receivers.Add(header.Device); DevicesChanged?.Invoke(receivers.Count);
            }
            IEnumerable<(Usage Usage, bool Down)> edges = [];
            var data = buffer + (int)headerSize;
            if (header.Type == 1 && length >= headerSize + 16)
            {
                var keyboard = Marshal.PtrToStructure<RawKeyboard>(data);
                edges = decoder.Keyboard(header.Device, keyboard.VirtualKey, (keyboard.Flags & 1) == 0);
            }
            else if (header.Type == 2 && length >= headerSize + 8)
            {
                int size = Marshal.ReadInt32(data), count = Marshal.ReadInt32(data, 4);
                if (size < 1 || count < 1 || (long)size * count > length - headerSize - 8) return;
                var reports = new byte[size * count]; Marshal.Copy(data + 8, reports, 0, reports.Length);
                if (!reportReaders.TryGetValue(header.Device, out var reader))
                    reportReaders[header.Device] = reader = HidReportReader.Create(header.Device);
                edges = reader != null ? reader.Read(decoder, header.Device, reports, size, count)
                    : decoder.Reports(header.Device, reports, size, count);
            }
            foreach (var (usage, down) in edges) Edge?.Invoke(usage, down);
        }
        finally { Marshal.FreeHGlobal(buffer); }
    }
    private bool Matches(nint device)
    {
        if (device == 0) return false;
        uint size = (uint)Marshal.SizeOf<DeviceInfo>();
        var info = new DeviceInfo { Size = size };
        // Prefer numeric HID identity, independent of transport/path spelling.
        if (GetRawInputDeviceInfo(device, 0x2000000B, ref info, ref size) != uint.MaxValue && info.Type == 2)
            return info.VendorId == profile.VendorId && info.ProductId == profile.ProductId;
        // Keyboard device-info has no VID/PID; use its explicit interface ID.
        return ReceiverDecoder.Matches(DeviceName(device), profile);
    }
    private void RemoveReader(nint device)
    {
        if (reportReaders.Remove(device, out var reader)) reader?.Dispose();
    }
    private static string DeviceName(nint device)
    {
        uint size = 0; GetRawInputDeviceInfo(device, 0x20000007, null, ref size);
        if (size is 0 or > 4096) return "";
        var text = new StringBuilder((int)size + 1);
        return GetRawInputDeviceInfo(device, 0x20000007, text, ref size) == uint.MaxValue ? "" : text.ToString();
    }
    public void Dispose()
    {
        if(!listeners.Remove(this))return;
        foreach(var reader in reportReaders.Values)reader?.Dispose();
        reportReaders.Clear();receivers.Clear();decoder.Clear();
        if(listeners.Count==0){hub?.Dispose();hub=null;}
    }
    [StructLayout(LayoutKind.Sequential)] private readonly record struct RawDevice(ushort Page, ushort Usage, uint Flags, nint Target);
    [StructLayout(LayoutKind.Sequential)] private struct DeviceEntry { public nint Device; public uint Type; }
    [StructLayout(LayoutKind.Sequential)] private struct RawHeader { public uint Type, Size; public nint Device, WParam; }
    [StructLayout(LayoutKind.Sequential)] private struct RawKeyboard { public ushort Scan, Flags, Reserved, VirtualKey; public uint Message, Extra; }
    // RID_DEVICE_INFO: header followed by a 24-byte union (keyboard is largest).
    [StructLayout(LayoutKind.Explicit, Size = 32)] private struct DeviceInfo
    {
        [FieldOffset(0)] public uint Size;
        [FieldOffset(4)] public uint Type;
        [FieldOffset(8)] public uint VendorId;
        [FieldOffset(12)] public uint ProductId;
    }
    [DllImport("user32.dll", SetLastError = true)] private static extern bool RegisterRawInputDevices([In] RawDevice[] devices, uint count, uint size);
    [DllImport("user32.dll")] private static extern uint GetRawInputData(nint input, uint command, nint data, ref uint size, uint headerSize);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern uint GetRawInputDeviceInfo(nint device, uint command, StringBuilder? data, ref uint size);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern uint GetRawInputDeviceInfo(nint device, uint command, ref DeviceInfo data, ref uint size);
    [DllImport("user32.dll")] private static extern uint GetRawInputDeviceList([Out] DeviceEntry[]? entries, ref uint count, uint size);
}
