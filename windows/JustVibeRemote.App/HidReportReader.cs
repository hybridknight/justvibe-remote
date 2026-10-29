using System.Runtime.InteropServices;
using JustVibeRemote.Core;

namespace JustVibeRemote;

// Raw Input and the OS HID parser work for both USB and paired Bluetooth HID.
// No device is opened exclusively and no vendor-specific commands are sent.
internal sealed class HidReportReader : IDisposable
{
    private const int Success = 0x00110000;
    private nint preparsed;
    private readonly int reportLength;
    private readonly Dictionary<ushort, ushort[]> buffers = [];
    internal delegate int ReadUsages(ushort page, ushort[] usages, ref uint length, byte[] report);
    private readonly ReadUsages readUsages;

    private HidReportReader(nint data, int length)
    {
        preparsed = data; reportLength = length;
        readUsages = (ushort page, ushort[] usages, ref uint count, byte[] report) =>
            HidP_GetUsages(0, page, 0, usages, ref count, preparsed, report, (uint)report.Length);
        foreach (ushort page in new ushort[] { 1, 7, 12 })
        {
            uint maximum = HidP_MaxUsageListLength(0, page, data);
            if (maximum is > 0 and <= 4096) buffers[page] = new ushort[maximum];
        }
    }

    // Keep report processing testable without connecting hardware or loading
    // Windows DLLs. Production always uses Create and the native HID parser.
    internal HidReportReader(int length, Dictionary<ushort, int> capacities, ReadUsages read)
    {
        reportLength = length; readUsages = read;
        foreach (var (page, capacity) in capacities)
            if (capacity is > 0 and <= 4096) buffers[page] = new ushort[capacity];
    }
    private bool disposed;

    public static HidReportReader? Create(nint device)
    {
        uint size = 0;
        if (GetRawInputDeviceInfo(device, 0x20000005, 0, ref size) == uint.MaxValue || size is 0 or > 65536) return null;
        nint data = Marshal.AllocHGlobal((int)size);
        try
        {
            if (GetRawInputDeviceInfo(device, 0x20000005, data, ref size) == uint.MaxValue ||
                HidP_GetCaps(data, out var caps) != Success || caps.InputReportByteLength is 0 or > 4096) return null;
            var reader = new HidReportReader(data, caps.InputReportByteLength);
            data = 0; // Ownership transfers only after successful construction.
            return reader;
        }
        finally { if (data != 0) Marshal.FreeHGlobal(data); }
    }

    public IEnumerable<(Usage Usage, bool Down)> Read(ReceiverDecoder decoder, nint device, byte[] reports, int size, int count)
    {
        if (disposed || size < 1 || size != reportLength || count < 1 || (long)size * count != reports.Length) return [];
        var edges = new List<(Usage, bool)>();
        var report = new byte[size];
        for (int offset = 0; offset < reports.Length; offset += size)
        {
            Array.Copy(reports, offset, report, 0, size);
            foreach (var (page, usages) in buffers)
            {
                uint length = (uint)usages.Length;
                // Incompatible IDs and parser errors leave earlier held state
                // alone. Never reinterpret a failed parse as the legacy format.
                if (readUsages(page, usages, ref length, report) != Success || length > usages.Length) continue;
                edges.AddRange(decoder.Buttons(device, report[0], page, usages.Take((int)length).Select(u => (uint)u)));
            }
        }
        return edges;
    }

    public void Dispose()
    {
        if (preparsed != 0) Marshal.FreeHGlobal(preparsed);
        preparsed = 0;
        disposed = true;
    }

    // HIDP_CAPS is 64 bytes; only the input length is needed here.
    [StructLayout(LayoutKind.Explicit, Size = 64)]
    private struct HidCaps { [FieldOffset(4)] public ushort InputReportByteLength; }
    [DllImport("user32.dll", EntryPoint = "GetRawInputDeviceInfoW")]
    private static extern uint GetRawInputDeviceInfo(nint device, uint command, nint data, ref uint size);
    [DllImport("hid.dll")] private static extern int HidP_GetCaps(nint data, out HidCaps caps);
    [DllImport("hid.dll")] private static extern uint HidP_MaxUsageListLength(int type, ushort page, nint data);
    [DllImport("hid.dll")] private static extern int HidP_GetUsages(int type, ushort page, ushort collection, [Out] ushort[] usages, ref uint length, nint data, [In] byte[] report, uint reportLength);
}
