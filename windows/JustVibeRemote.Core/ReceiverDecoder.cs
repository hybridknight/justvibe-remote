using System.Text.RegularExpressions;

namespace JustVibeRemote.Core;

public sealed class ReceiverDecoder(DeviceProfile profile)
{
    private readonly Dictionary<(nint, string), HashSet<Usage>> held = [];
    public static bool Matches(string path, DeviceProfile profile)
    {
        // Windows exposes both USB-style HID IDs and Bluetooth PnP IDs.
        // Bluetooth's first four VID digits identify the vendor-ID authority.
        var match = Regex.Match(path, @"(?:^|[\\#&_])VID(?:_([0-9A-F]{4})&PID_|&(?:0001|0002)([0-9A-F]{4})_PID&)([0-9A-F]{4})(?:[&#\\]|$)", RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
        return match.Success && Convert.ToInt32(match.Groups[1].Success ? match.Groups[1].Value : match.Groups[2].Value, 16) == profile.VendorId && Convert.ToInt32(match.Groups[3].Value, 16) == profile.ProductId;
    }
    public void Remove(nint handle)
    {
        foreach (var key in held.Keys.Where(k => k.Item1 == handle).ToArray()) held.Remove(key);
    }
    public void Clear() => held.Clear();
    // A successful descriptor parse supplies one snapshot per report and page.
    // An empty snapshot releases that stream; failed or unrelated reports must
    // not submit a snapshot. Other interfaces/report IDs remain held.
    public IEnumerable<(Usage Usage, bool Down)> Buttons(nint handle, byte reportId, uint page, IEnumerable<uint> codes) =>
        Snapshot((handle, $"hid:{reportId}:{page}"), codes.Select(code => new Usage(page, code)).Where(u => u.IsButton).ToHashSet());
    private IEnumerable<(Usage Usage, bool Down)> Snapshot((nint, string) key, HashSet<Usage> current)
    {
        var previous = held.Values.SelectMany(v => v).ToHashSet();
        if (current.Count == 0) held.Remove(key); else held[key] = current;
        var next = held.Values.SelectMany(v => v).ToHashSet();
        return previous.Except(next).Select(u => (u, false)).Concat(next.Except(previous).Select(u => (u, true))).ToArray();
    }
    public IEnumerable<(Usage Usage, bool Down)> Keyboard(nint handle, uint virtualKey, bool down)
    {
        var usage = FromVirtualKey(virtualKey);
        if (usage is null || !usage.Value.IsButton) return [];
        var key = (handle, "keyboard");
        var state = new HashSet<Usage>(held.GetValueOrDefault(key) ?? []);
        if (down) state.Add(usage.Value); else state.Remove(usage.Value);
        return Snapshot(key, state);
    }
    public IEnumerable<(Usage Usage, bool Down)> Reports(nint handle, byte[] bytes, int reportSize, int count)
    {
        if (reportSize != profile.ConsumerReportLength || count < 1 || (long)reportSize * count != bytes.Length) return [];
        var result = new List<(Usage, bool)>();
        for (var offset = 0; offset < bytes.Length; offset += reportSize)
        {
            if (bytes[offset] != profile.ConsumerReportId) continue;
            var code = (uint)(bytes[offset + profile.ConsumerUsageOffset] | bytes[offset + profile.ConsumerUsageOffset + 1] << 8);
            var key = (handle, "consumer");
            HashSet<Usage> current = code == 0 ? [] : [new(12, code)];
            result.AddRange(Snapshot(key, current));
        }
        return result;
    }
    public static Usage? FromVirtualKey(uint key)
    {
        if (key is >= 0x41 and <= 0x5A) return new(7, key - 0x41 + 4);
        if (key is >= 0x31 and <= 0x39) return new(7, key - 0x31 + 0x1E);
        if (key is >= 0x61 and <= 0x69) return new(7, key - 0x61 + 0x59);
        if (key is >= 0x70 and <= 0x7B) return new(7, key - 0x70 + 0x3A);
        if (key is >= 0x7C and <= 0x87) return new(7, key - 0x7C + 0x68);
        return key switch
        {
            0x0D => new(7, 0x28), 0x1B => new(7, 0x29), 0x08 => new(7, 0x2A),
            0x09 => new(7, 0x2B), 0x20 => new(7, 0x2C), 0x24 => new(7, 0x4A),
            0x30 => new(7, 0x27), 0x60 => new(7, 0x62),
            0x21 => new(7, 0x4B), 0x22 => new(7, 0x4E), 0x23 => new(7, 0x4D),
            0x2D => new(7, 0x49), 0x2E => new(7, 0x4C),
            0x25 => new(7, 0x50), 0x26 => new(7, 0x52), 0x27 => new(7, 0x4F), 0x28 => new(7, 0x51),
            0x5D => new(7, 0x65), 0xAE => new(12, 0xEA), 0xAF => new(12, 0xE9),
            0xAD => new(12, 0xE2), 0xB0 => new(12, 0xB5), 0xB1 => new(12, 0xB6),
            0xB2 => new(12, 0xB7), 0xB3 => new(12, 0xCD),
            0xA6 => new(12, 0x224), 0xAC => new(12, 0x223), _ => null
        };
    }
}
