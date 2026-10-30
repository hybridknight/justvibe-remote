using System.Diagnostics;
using System.Text.Json;
using JustVibeRemote.Core;
namespace JustVibeRemote;

internal static class LocalAppRegistration
{
    public static PluginManifest Install(string path,string? shortcut,string directory,PluginCatalog catalog)
    {
        path=Path.GetFullPath(path);
        if(!File.Exists(path)||!path.EndsWith(".exe",StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("Choose a Windows application (.exe).");
        var processName=Path.GetFileNameWithoutExtension(path);
        var existing=catalog.Apps.Where(p=>p.App!.Targets.GetValueOrDefault("windows")?.Names.Contains(processName,StringComparer.OrdinalIgnoreCase)==true).ToArray();
        if(existing.Length>1)throw new InvalidOperationException("Several profiles target this app. Select one and use Locate app to distinguish it.");
        if(existing.Length==1)return existing[0];
        var actions=new Dictionary<string,PluginAction>{["focus"]=new(){Operation="focus"}};
        foreach(var (action,key) in new[]{("send","ENTER"),("backspace","BACKSPACE"),("escape","ESC")})actions[action]=new(){Operation="tap-shortcut",Shortcuts=new(){["windows"]=key}};
        if(!string.IsNullOrWhiteSpace(shortcut))
        {PluginManifest.ValidateShortcut(shortcut,"windows");actions["dictate"]=new(){Operation="hold-shortcut",Shortcuts=new(){["windows"]=shortcut.Trim().ToUpperInvariant()}};}
        var name=FileVersionInfo.GetVersionInfo(path).ProductName;
        if(string.IsNullOrWhiteSpace(name))name=processName;
        var plugin=new PluginManifest{SchemaVersion=1,ApiVersion=1,Id="local.justviberemote.app."+Guid.NewGuid().ToString("D"),Version="1.0.0",Name=name[..Math.Min(100,name.Length)],Author="Added on this PC",Kind="app",Platforms=["windows"],Capabilities=["target.focus","input.shortcuts"],App=new(){Adapter="shortcuts",Targets=new(){["windows"]=new(){Names=[processName]}},Actions=actions}};
        plugin.Validate();Directory.CreateDirectory(directory);
        var staging=Path.Combine(directory,".adding-"+Guid.NewGuid().ToString("N"));Directory.CreateDirectory(staging);
        try
        {
            File.WriteAllText(Path.Combine(staging,"plugin.json"),JsonSerializer.Serialize(plugin,ConfigurationStore.Json));
            File.WriteAllText(Path.Combine(staging,"README.md"),"Locally added Windows app. Process identity is a routing rule, not publisher authentication. Confirm shortcuts in the app. Licensing is undecided.\n");
            Directory.Move(staging,Path.Combine(directory,plugin.Id));
        }
        finally{if(Directory.Exists(staging))Directory.Delete(staging,true);}
        return plugin;
    }
}
internal sealed class ShortcutRecorder:WorkspaceTextBox
{
    private bool recording;private string previous="";
    private readonly WorkspaceButton record;
    public ShortcutRecorder()
    {
        AccessibleName="Dictation shortcut";PlaceholderText="e.g. CTRL+SHIFT+D";
        record=WorkspaceStyle.Button("Record",BeginRecording);record.AccessibleName="Record dictation shortcut";record.AutoSize=false;record.MinimumSize=Size.Empty;record.Margin=Padding.Empty;Controls.Add(record);
        DoubleClick+=(_,_)=>BeginRecording();
    }
    protected override int EditRightInset=>(int)Math.Round(104*DeviceDpi/96f);
    protected override void OnLayout(LayoutEventArgs e)
    {
        base.OnLayout(e);if(record!=null)record.Bounds=new Rectangle(FieldBounds.Right+(int)Math.Round(12*DeviceDpi/96f),0,EditRightInset-(int)Math.Round(12*DeviceDpi/96f),Height);
    }
    internal void VerifyPresentation()
    {
        PerformLayout();
        if(!ClientRectangle.Contains(record.Bounds)||record.Left<FieldBounds.Right+(int)Math.Round(8*DeviceDpi/96f))throw new InvalidOperationException("Shortcut Record button overlaps the input or is clipped.");
    }
    private void BeginRecording(){previous=Text;recording=true;ReadOnly=true;Text="Press a shortcut…";FocusEdit();}
    private void CancelRecording(){recording=false;ReadOnly=false;Text=previous;}
    protected override bool ProcessEditCommand(Keys keys)
    {
        if(!recording)return base.ProcessEditCommand(keys);
        var e=new KeyEventArgs(keys);
        if(e.KeyCode==Keys.Tab){CancelRecording();return false;}
        CaptureShortcut(e);return true;
    }
    protected override void OnKeyDown(KeyEventArgs e)
    {
        if(!recording){base.OnKeyDown(e);return;}
        if(e.KeyCode==Keys.Tab){CancelRecording();base.OnKeyDown(e);return;}
        CaptureShortcut(e);
    }
    private void CaptureShortcut(KeyEventArgs e)
    {
        e.SuppressKeyPress=true;e.Handled=true;
        if(e.KeyCode==Keys.Escape){CancelRecording();return;}
        if(e.KeyCode==Keys.RMenu||e.KeyCode==Keys.Menu&&(GetKeyState(0xA5)&0x8000)!=0){Text="RALT";recording=false;ReadOnly=false;return;}
        string? key=e.KeyCode switch{Keys.Enter=>"ENTER",Keys.Space=>"SPACE",Keys.Back=>"BACKSPACE",_ when e.KeyCode>=Keys.A&&e.KeyCode<=Keys.Z=>e.KeyCode.ToString(),_=>null};
        if(key==null)return;
        var parts=new List<string>();if(e.Control)parts.Add("CTRL");if(e.Alt)parts.Add("ALT");if(e.Shift)parts.Add("SHIFT");parts.Add(key);
        Text=string.Join('+',parts);recording=false;ReadOnly=false;
    }
    [System.Runtime.InteropServices.DllImport("user32.dll")]private static extern short GetKeyState(int key);
    protected override void OnLeave(EventArgs e){if(recording)CancelRecording();base.OnLeave(e);}
}
internal sealed class VoiceTypingSetup:Form
{
    public VoiceTypingSetup(RemoteController controller)
    {
        Text="Dictation in any app";ClientSize=new Size(640,500);MinimumSize=new Size(600,480);StartPosition=FormStartPosition.CenterParent;Font=WorkspaceStyle.Text();AutoScaleMode=AutoScaleMode.Dpi;BackColor=Color.White;
        var stack=WorkspaceStyle.Stack(584);stack.Dock=DockStyle.Fill;stack.AutoSize=false;stack.AutoScroll=true;stack.Padding=new Padding(WorkspaceStyle.Inset);Controls.Add(stack);
        stack.Controls.Add(WorkspaceStyle.Label("Dictation in any app",18,true,true,560));
        stack.Controls.Add(WorkspaceStyle.Label("Windows voice typing uses Win+H in the focused text field. Windows controls listening; use its microphone panel to stop it. This does not record or route audio through JustVibe.",10,false,false,560));
        var mode=new WorkspacePicker{DropDownStyle=ComboBoxStyle.DropDownList,Width=540,Margin=new Padding(0,0,0,16)};
        mode.Items.AddRange(new object[]{"Off","When app dictation is not configured","In every app"});
        mode.SelectedIndex=(int)controller.Config.VoiceTyping.Mode;
        var bindings=controller.Config.Bindings.Where(b=>b.ControlID!=null).ToArray();
        var button=new WorkspacePicker{DropDownStyle=ComboBoxStyle.DropDownList,Width=540,Margin=new Padding(0,0,0,16)};
        button.Items.AddRange(bindings.Select(b=>(object)b.Name).ToArray());
        int selected=Array.FindIndex(bindings,b=>b.ControlID==controller.Config.VoiceTyping.ControlID);button.SelectedIndex=selected>=0?selected:bindings.Length>0?0:-1;
        var confirmed=new CheckBox{Text="I have checked Windows voice typing with Win+H",AutoSize=true,Checked=controller.Config.VoiceTyping.Confirmed,Margin=new Padding(0,0,0,16)};
        stack.Controls.Add(WorkspaceStyle.Label("Use Windows voice typing",10,true));stack.Controls.Add(mode);stack.Controls.Add(WorkspaceStyle.Label("Remote button",10,true));stack.Controls.Add(button);stack.Controls.Add(confirmed);
        stack.Controls.Add(WorkspaceStyle.Button("Open Windows speech settings",()=>WorkspaceStyle.Open("ms-settings:speech")));
        stack.Controls.Add(WorkspaceStyle.Row(WorkspaceStyle.Button("Cancel",Close),WorkspaceStyle.Button("Save",()=>{
            try{controller.Update(controller.Config with{VoiceTyping=new((VoiceTypingMode)mode.SelectedIndex,button.SelectedIndex>=0?bindings[button.SelectedIndex].ControlID:null,confirmed.Checked)});Close();}
            catch(Exception error){MessageBox.Show(this,error.Message,Text);}
        },true)));WorkspaceStyle.Apply(this);
    }
}
