namespace JustVibeRemote.Core;
public sealed record MicrophonePreference(string Id,string Name,bool GuardDictation);
public static class MicrophonePolicy
{
    public static string? Issue(MicrophonePreference? preference,IEnumerable<string> available,IReadOnlyList<string> defaults)
    {
        if(preference?.GuardDictation!=true)return null;
        if(preference.Id.Length==0||!available.Contains(preference.Id))return "Selected remote microphone is disconnected. Open Microphone test; no shortcut was sent.";
        if(defaults.Count==0||defaults.Any(id=>id!=preference.Id))return "System input is not the selected remote microphone. Open Microphone test; no shortcut was sent.";
        return null;
    }
}
public sealed class PCMPreview(int sampleRate)
{
    private readonly List<short> samples=[];
    public int SampleRate { get; }=sampleRate;
    public int Count=>samples.Count;
    public bool Full=>Count>=SampleRate*5;
    public double Level { get; private set; }
    public void Append(ReadOnlySpan<byte> bytes)
    {
        if(SampleRate is <8000 or >192000)return;
        int count=Math.Min(bytes.Length/2,Math.Max(0,SampleRate*5-Count));double energy=0;
        for(int i=0;i<count;i++){short sample=System.Buffers.Binary.BinaryPrimitives.ReadInt16LittleEndian(bytes.Slice(i*2,2));samples.Add(sample);energy+=Math.Pow(sample/32768.0,2);}
        if(count>0)Level=Math.Sqrt(energy/count);
    }
    public byte[] Wave()
    {
        using var stream=new MemoryStream();using var writer=new BinaryWriter(stream);
        writer.Write(System.Text.Encoding.ASCII.GetBytes("RIFF"));writer.Write(36+Count*2);writer.Write(System.Text.Encoding.ASCII.GetBytes("WAVEfmt "));
        writer.Write(16);writer.Write((short)1);writer.Write((short)1);writer.Write(SampleRate);writer.Write(SampleRate*2);writer.Write((short)2);writer.Write((short)16);
        writer.Write(System.Text.Encoding.ASCII.GetBytes("data"));writer.Write(Count*2);foreach(short sample in samples)writer.Write(sample);return stream.ToArray();
    }
}
