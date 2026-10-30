using System.Diagnostics;
using System.Media;
using JustVibeRemote.Core;

namespace JustVibeRemote;
internal sealed class MicrophoneTest:Form
{
    private readonly RemoteController controller;
    private readonly WorkspacePicker picker=new(){DropDownStyle=ComboBoxStyle.DropDownList,Width=570};
    private readonly Label source=Block(""),system=Block(""),result=Block("Choose your remote’s microphone, then start a short test.");
    private readonly ProgressBar meter=new(){Width=570,Height=22};
    private readonly CheckBox protect=new(){Text="Block remote dictation when system input differs",AutoSize=true,Checked=true};
    private readonly WorkspaceButton record,play,stop,clear;
    private readonly System.Windows.Forms.Timer timer=new(){Interval=100};
    private List<AudioInput> inputs=[];
    private MicrophoneCapture? audio;
    private SoundPlayer? player;private MemoryStream? playback;
    private DateTime started,lastScan;private bool ended,loading;
    public MicrophoneTest(RemoteController controller)
    {
        this.controller=controller;record=WorkspaceStyle.Button("Start 5-second test",()=>Try(Start),true);play=WorkspaceStyle.Button("Play back",()=>Try(Play));stop=Button("Stop",Stop);clear=Button("Clear preview",Clear);Text="Microphone test";ClientSize=new Size(650,700);MinimumSize=new Size(650,600);Font=WorkspaceStyle.Text(10);BackColor=Color.White;StartPosition=FormStartPosition.CenterParent;AutoScaleMode=AutoScaleMode.Dpi;
        var stack=new FlowLayoutPanel{Dock=DockStyle.Fill,FlowDirection=FlowDirection.TopDown,WrapContents=false,AutoScroll=true,Padding=new Padding(WorkspaceStyle.Inset)};Controls.Add(stack);
        var heading=Block("Hear your remote’s microphone");heading.Font=WorkspaceStyle.Text(21,true,true);stack.Controls.Add(heading);
        stack.Controls.Add(Block("Choose the remote’s USB audio input. Names can be generic; confirm the source by speaking near the remote, away from the computer."));
        stack.Controls.Add(picker);var devicesRow=new FlowLayoutPanel{AutoSize=true};devicesRow.Controls.Add(Button("Refresh",Reload));devicesRow.Controls.Add(Button("Microphone permissions…",()=>Process.Start(new ProcessStartInfo("ms-settings:privacy-microphone"){UseShellExecute=true})));stack.Controls.Add(devicesRow);stack.Controls.Add(source);stack.Controls.Add(meter);stack.Controls.Add(result);
        var actions=new FlowLayoutPanel{AutoSize=true,WrapContents=true,MaximumSize=new Size(570,0)};actions.Controls.Add(record);actions.Controls.Add(stop);actions.Controls.Add(play);actions.Controls.Add(clear);stack.Controls.Add(actions);
        stack.Controls.Add(Block("Hold the remote’s mic button while speaking if needed. The five-second mono preview stays in memory, is never uploaded, and is deleted on close."));
        stack.Controls.Add(system);stack.Controls.Add(Button("Open Windows Sound input settings",()=>Process.Start(new ProcessStartInfo("ms-settings:sound"){UseShellExecute=true})));
        stack.Controls.Add(protect);stack.Controls.Add(Block("Select this mic as both default input and default communications input in Windows. ChatGPT input is not verified here: choose the same mic or System Default in your app, close this test, and dictate a phrase there."));
        var finish=new FlowLayoutPanel{AutoSize=true};finish.Controls.Add(Button("Save microphone choice",Save,true));finish.Controls.Add(Button("Close",Close));stack.Controls.Add(finish);
        if(controller.Config.Microphones.TryGetValue(controller.Config.DevicePluginID,out var preference))protect.Checked=preference.GuardDictation;
        picker.SelectedIndexChanged+=(_,_)=>{if(!loading)Try(()=>{Clear();UpdateLabels();});};
        timer.Tick+=(_,_)=>Try(RefreshTest);Shown+=(_,_)=>{controller.BeginMicrophoneTest();timer.Start();};
        FormClosing+=(_,e)=>{if(ended)return;try{Clear();ended=true;timer.Stop();controller.EndMicrophoneTest();}catch(Exception error){e.Cancel=true;MessageBox.Show(this,error.Message,"Microphone test");}};
        WorkspaceStyle.Apply(this);
        Reload();
    }
    private static Label Block(string text)=>new(){Text=text,AutoSize=true,MaximumSize=new Size(570,0),Margin=new Padding(0,0,0,WorkspaceStyle.Controls),ForeColor=Palette.Ink};
    private static WorkspaceButton Button(string text,Action action,bool primary=false)=>WorkspaceStyle.Button(text,()=>{try{action();}catch(Exception error){MessageBox.Show(error.Message,"Microphone test");}},primary);
    private AudioInput? Selected=>picker.SelectedIndex>0&&picker.SelectedIndex<=inputs.Count?inputs[picker.SelectedIndex-1]:null;
    private void Reload()
    {
        string? id=Selected?.Id??controller.Config.Microphones.GetValueOrDefault(controller.Config.DevicePluginID)?.Id;Clear();inputs=AudioInputs.List();loading=true;picker.Items.Clear();picker.Items.Add("Select microphone…");
        foreach(var input in inputs)picker.Items.Add(input.Name+" · input "+(input.Device+1));
        int index=inputs.FindIndex(d=>d.Id==id);picker.SelectedIndex=index<0?0:index+1;loading=false;UpdateLabels();
    }
    private void UpdateLabels()
    {
        source.Text=Selected is {} input?"Test input: "+input.Name:"No microphone selected. No input fallback is used.";
        var defaults=AudioInputs.Defaults();
        system.Text=Selected!=null&&defaults.Count==3&&defaults.All(id=>id==Selected.Id)?"All Windows input defaults match this mic. Your app can still override them.":"System input defaults do not all match the selected mic (or could not be read). Change them in Sound settings before protected dictation.";
        record.Enabled=Selected!=null&&audio?.Recording!=true;play.Enabled=audio?.Preview?.Count>0;stop.Enabled=audio?.Recording==true;clear.Enabled=audio?.Preview?.Count>0;
    }
    private void Start()
    {
        if(Selected is not {} input)return;Clear();audio=new MicrophoneCapture();audio.Start(input);started=DateTime.UtcNow;UpdateLabels();
    }
    private void RefreshTest()
    {
        if((DateTime.UtcNow-lastScan).TotalSeconds>1)
        {
            lastScan=DateTime.UtcNow;
            if(audio?.Recording==true&&!AudioInputs.List().Any(d=>d.Id==audio.InputID)){audio.Stop();result.Text="Microphone disconnected. Test stopped; no other input was used.";}
            UpdateLabels();
        }
        meter.Value=Math.Clamp((int)((audio?.Level??0)*350),0,100);
        if(audio?.Error is string error){audio.Stop();result.Text=error;UpdateLabels();return;}
        if(audio?.Recording==true)
        {
            result.Text=$"Testing {Selected?.Name} · {Math.Max(0,5-(int)(DateTime.UtcNow-started).TotalSeconds)} seconds left · "+(audio.Level>0.01?"Sound detected":"Very quiet — hold the mic button and speak");
            if(audio.Preview?.Full==true||(DateTime.UtcNow-started).TotalSeconds>=5)Stop();
        }
    }
    private void Stop(){audio?.Stop();result.Text=audio?.Preview?.Count>0?"Test finished. Play it back to hear this input. Nothing was uploaded.":"No audio received. Hold the remote microphone button and try again.";UpdateLabels();}
    private void Play()
    {
        audio?.Stop();player?.Stop();player?.Dispose();playback?.Dispose();
        if(audio?.Preview?.Count>0){playback=new MemoryStream(audio.Preview.Wave(),false);player=new SoundPlayer(playback);player.Load();player.Play();}UpdateLabels();
    }
    private void Clear(){audio?.Dispose();audio=null;player?.Stop();player?.Dispose();player=null;playback?.Dispose();playback=null;meter.Value=0;result.Text="Preview cleared. Ready for a new test.";UpdateLabels();}
    private void Save()
    {
        if(Selected is not {} input){result.Text="Choose a microphone first.";return;}
        Try(()=>{var microphones=new Dictionary<string,MicrophonePreference>(controller.Config.Microphones){[controller.Config.DevicePluginID]=new(input.Id,input.Name,protect.Checked)};controller.Update(controller.Config with{Microphones=microphones});result.Text="Saved for this remote. Close the test and try dictation in your app.";});
    }
    private void Try(Action action){try{action();}catch(Exception error){result.Text=error.Message;}}
    protected override void Dispose(bool disposing){if(disposing){timer.Dispose();if(!ended){audio?.Dispose();player?.Dispose();playback?.Dispose();controller.EndMicrophoneTest();}}base.Dispose(disposing);}
}
