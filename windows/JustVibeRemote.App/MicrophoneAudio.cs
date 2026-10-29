using System.Runtime.InteropServices;
using JustVibeRemote.Core;

namespace JustVibeRemote;
internal sealed record AudioInput(uint Device,string Id,string Name);
internal static class AudioInputs
{
    public static List<AudioInput> List()
    {
        var result=new List<AudioInput>();
        for(uint index=0;index<NativeAudio.waveInGetNumDevs();index++)
        {
            if(NativeAudio.waveInGetDevCapsW((nuint)index,out var caps,(uint)Marshal.SizeOf<NativeAudio.Caps>())!=0)continue;
            string id=Endpoint(index);if(id.Length>0)result.Add(new(index,id,caps.Name));
        }
        return result;
    }
    private static string Endpoint(uint index)
    {
        nint size=Marshal.AllocHGlobal(8);Marshal.WriteInt64(size,0);
        try
        {
            if(NativeAudio.waveInMessage((nint)index,0x812,size,0)!=0)return "";
            int bytes=Marshal.ReadInt32(size);if(bytes<2||bytes>65536)return "";
            nint buffer=Marshal.AllocHGlobal(bytes);
            try{return NativeAudio.waveInMessage((nint)index,0x811,buffer,(nint)bytes)==0?Marshal.PtrToStringUni(buffer)??"":"";}
            finally{Marshal.FreeHGlobal(buffer);}
        }
        finally{Marshal.FreeHGlobal(size);}
    }
    public static List<string> Defaults()
    {
        IDeviceEnumerator? enumerator=null;
        try
        {
            enumerator=(IDeviceEnumerator)new DeviceEnumerator();var ids=new List<string>();
            for(int role=0;role<3;role++)
            {
                Marshal.ThrowExceptionForHR(enumerator.GetDefaultAudioEndpoint(1,role,out var device));
                try
                {
                    Marshal.ThrowExceptionForHR(device.GetId(out var ptr));
                    try{ids.Add(Marshal.PtrToStringUni(ptr)??"");}finally{Marshal.FreeCoTaskMem(ptr);}
                }finally{Marshal.ReleaseComObject(device);}
            }
            return ids;
        }
        catch(COMException){return [];}
        finally{if(enumerator!=null)Marshal.ReleaseComObject(enumerator);}
    }
    public static void Check(MicrophonePreference? preference)
    {
        if(preference?.GuardDictation!=true)return;
        if(MicrophonePolicy.Issue(preference,List().Select(d=>d.Id),Defaults()) is string issue)throw new InvalidOperationException(issue);
    }
    [ComImport,Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]private class DeviceEnumerator{}
    [ComImport,Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]private interface IDeviceEnumerator
    {
        [PreserveSig]int EnumAudioEndpoints(int flow,uint mask,out nint collection);
        [PreserveSig]int GetDefaultAudioEndpoint(int flow,int role,out IDevice device);
        [PreserveSig]int GetDevice([MarshalAs(UnmanagedType.LPWStr)]string id,out IDevice device);
        [PreserveSig]int RegisterEndpointNotificationCallback(nint client);
        [PreserveSig]int UnregisterEndpointNotificationCallback(nint client);
    }
    [ComImport,Guid("D666063F-1587-4E43-81F1-B948E807363F"),InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]private interface IDevice
    {
        [PreserveSig]int Activate(ref Guid iid,uint context,nint parameters,out nint instance);
        [PreserveSig]int OpenPropertyStore(uint access,out nint store);
        [PreserveSig]int GetId(out nint id);
        [PreserveSig]int GetState(out uint state);
    }
}

/// Window-message capture keeps all buffer ownership and teardown on the UI thread.
internal sealed class MicrophoneCapture:NativeWindow,IDisposable
{
    private nint handle;
    private bool running,disposed;
    private readonly Dictionary<nint,nint> buffers=[];
    public PCMPreview? Preview { get; private set; }
    public string InputID { get; private set; }="";
    public bool Recording=>running;
    private DateTime lastAudioAt;
    public double Level=>running&&(DateTime.UtcNow-lastAudioAt).TotalSeconds<0.4?Preview?.Level??0:0;
    public void Start(AudioInput selected)
    {
        if(disposed)throw new ObjectDisposedException(nameof(MicrophoneCapture));
        if(handle!=0)throw new InvalidOperationException("Stop the previous test first.");
        var matches=AudioInputs.List().Where(d=>d.Id==selected.Id).ToList();
        if(matches.Count!=1)throw new InvalidOperationException("Selected microphone is unavailable or ambiguous. No other input was opened.");
        CreateHandle(new CreateParams{Caption="JustVibe Remote audio preview",Parent=new nint(-3)});
        uint error=1;int rate=0;
        foreach(int candidate in new[]{48000,44100,16000,8000})
        {
            var format=new NativeAudio.Format{Tag=1,Channels=1,Rate=(uint)candidate,Average=(uint)candidate*2,Block=2,Bits=16};
            error=NativeAudio.waveInOpen(out handle,matches[0].Device,ref format,Handle,0,0x10000);
            if(error==0){rate=candidate;break;}
            handle=0;
        }
        if(error!=0){DestroyHandle();throw new InvalidOperationException($"Cannot open this mic (Windows audio error {error}). Check microphone access in Settings → Privacy & security → Microphone.");}
        if(!AudioInputs.List().Any(d=>d.Device==matches[0].Device&&d.Id==selected.Id)){Stop();throw new InvalidOperationException("Microphone list changed while opening. Test cancelled without accepting audio.");}
        Preview=new PCMPreview(rate);InputID=selected.Id;
        try
        {
            for(int i=0;i<4;i++)
            {
                nint data=Marshal.AllocHGlobal(4096),header=Marshal.AllocHGlobal(Marshal.SizeOf<NativeAudio.Header>());
                Marshal.StructureToPtr(new NativeAudio.Header{Data=data,Length=4096},header,false);buffers.Add(header,data);
                NativeAudio.Check(NativeAudio.waveInPrepareHeader(handle,header,NativeAudio.HeaderSize));
                NativeAudio.Check(NativeAudio.waveInAddBuffer(handle,header,NativeAudio.HeaderSize));
            }
            running=true;NativeAudio.Check(NativeAudio.waveInStart(handle));
        }
        catch{Stop();throw;}
    }
    protected override void WndProc(ref Message message)
    {
        if(message.Msg==0x3C0&&running&&buffers.ContainsKey(message.LParam))
        {
            var header=Marshal.PtrToStructure<NativeAudio.Header>(message.LParam);
            int count=(int)Math.Min(header.Recorded,header.Length);var bytes=new byte[count];Marshal.Copy(header.Data,bytes,0,count);Preview?.Append(bytes);if(count>0)lastAudioAt=DateTime.UtcNow;
            if(Preview?.Full!=true)
            {
                uint error=NativeAudio.waveInAddBuffer(handle,message.LParam,NativeAudio.HeaderSize);
                if(error!=0){Error=$"Audio buffer failed ({error}); stop and retry the test.";running=false;}
            }
        }
        base.WndProc(ref message);
    }
    public string? Error { get; private set; }
    public void Stop()
    {
        running=false;
        if(handle==0)return;
        NativeAudio.Check(NativeAudio.waveInReset(handle));
        foreach(var pair in buffers.ToList())
        {
            // After reset, a prepared buffer can be unprepared. Retain any failed buffer rather than freeing driver-owned memory.
            uint error=NativeAudio.waveInUnprepareHeader(handle,pair.Key,NativeAudio.HeaderSize);
            if(error!=0)throw new InvalidOperationException($"Audio test could not release a buffer ({error}). Close the test and retry.");
            Marshal.FreeHGlobal(pair.Value);Marshal.FreeHGlobal(pair.Key);buffers.Remove(pair.Key);
        }
        NativeAudio.Check(NativeAudio.waveInClose(handle));handle=0;DestroyHandle();
    }
    public void Dispose(){if(disposed)return;Stop();Preview=null;disposed=true;GC.SuppressFinalize(this);}
}
internal static class NativeAudio
{
    [StructLayout(LayoutKind.Sequential,CharSet=CharSet.Unicode)]internal struct Caps{public ushort Manufacturer,Product;public uint Version;[MarshalAs(UnmanagedType.ByValTStr,SizeConst=32)]public string Name;public uint Formats;public ushort Channels,Reserved;}
    [StructLayout(LayoutKind.Sequential,Pack=2)]internal struct Format{public ushort Tag,Channels;public uint Rate,Average;public ushort Block,Bits,Extra;}
    [StructLayout(LayoutKind.Sequential)]internal struct Header{public nint Data;public uint Length,Recorded;public nuint User;public uint Flags,Loops;public nint Next;public nuint Reserved;}
    internal static uint HeaderSize= (uint)Marshal.SizeOf<Header>();
    internal static void Check(uint error){if(error!=0)throw new InvalidOperationException($"Windows audio error {error}. The microphone test stopped.");}
    [DllImport("winmm.dll")]internal static extern uint waveInGetNumDevs();
    [DllImport("winmm.dll",CharSet=CharSet.Unicode)]internal static extern uint waveInGetDevCapsW(nuint id,out Caps caps,uint size);
    [DllImport("winmm.dll")]internal static extern uint waveInMessage(nint id,uint message,nint first,nint second);
    [DllImport("winmm.dll")]internal static extern uint waveInOpen(out nint handle,uint id,ref Format format,nint callback,nint instance,uint flags);
    [DllImport("winmm.dll")]internal static extern uint waveInPrepareHeader(nint handle,nint header,uint size);
    [DllImport("winmm.dll")]internal static extern uint waveInUnprepareHeader(nint handle,nint header,uint size);
    [DllImport("winmm.dll")]internal static extern uint waveInAddBuffer(nint handle,nint header,uint size);
    [DllImport("winmm.dll")]internal static extern uint waveInStart(nint handle);
    [DllImport("winmm.dll")]internal static extern uint waveInReset(nint handle);
    [DllImport("winmm.dll")]internal static extern uint waveInClose(nint handle);
}
