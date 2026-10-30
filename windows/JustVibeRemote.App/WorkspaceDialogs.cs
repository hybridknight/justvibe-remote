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
internal sealed class ShortcutRecorder:TextBox
{
    private bool recording;private string previous="";
    public ShortcutRecorder(){AccessibleName="Dictation shortcut. Double-click to record a shortcut.";DoubleClick+=(_,_)=>{previous=Text;recording=true;ReadOnly=true;Text="Press a shortcut…";};}
    protected override void OnKeyDown(KeyEventArgs e)
    {
        if(!recording){base.OnKeyDown(e);return;}
        if(e.KeyCode==Keys.Tab){recording=false;ReadOnly=false;Text=previous;base.OnKeyDown(e);return;}
        e.SuppressKeyPress=true;e.Handled=true;
        if(e.KeyCode==Keys.Escape){recording=false;ReadOnly=false;Text=previous;return;}
        if(e.KeyCode==Keys.RMenu||e.KeyCode==Keys.Menu&&(GetKeyState(0xA5)&0x8000)!=0){Text="RALT";recording=false;ReadOnly=false;return;}
        string? key=e.KeyCode switch{Keys.Enter=>"ENTER",Keys.Space=>"SPACE",Keys.Back=>"BACKSPACE",_ when e.KeyCode>=Keys.A&&e.KeyCode<=Keys.Z=>e.KeyCode.ToString(),_=>null};
        if(key==null)return;
        var parts=new List<string>();if(e.Control)parts.Add("CTRL");if(e.Alt)parts.Add("ALT");if(e.Shift)parts.Add("SHIFT");parts.Add(key);
        Text=string.Join('+',parts);recording=false;ReadOnly=false;
    }
    [System.Runtime.InteropServices.DllImport("user32.dll")]private static extern short GetKeyState(int key);
    protected override void OnLeave(EventArgs e){if(recording){recording=false;ReadOnly=false;Text=previous;}base.OnLeave(e);}
}
internal sealed class VoiceTypingSetup:Form
{
    public VoiceTypingSetup(RemoteController controller)
    {
        Text="Dictation in any app";ClientSize=new Size(640,500);MinimumSize=new Size(600,480);StartPosition=FormStartPosition.CenterParent;Font=WorkspaceStyle.Text();AutoScaleMode=AutoScaleMode.Dpi;BackColor=Color.White;
        var stack=WorkspaceStyle.Stack(584);stack.Dock=DockStyle.Fill;stack.AutoSize=false;stack.AutoScroll=true;stack.Padding=new Padding(WorkspaceStyle.Inset);Controls.Add(stack);
        stack.Controls.Add(WorkspaceStyle.Label("Dictation in any app",18,true,true,560));
        stack.Controls.Add(WorkspaceStyle.Label("Windows voice typing uses Win+H in the focused text field. Windows controls listening; use its microphone panel to stop it. This does not record or route audio through JustVibe.",10,false,false,560));
        var mode=new ComboBox{DropDownStyle=ComboBoxStyle.DropDownList,Width=540,DataSource=new[]{"Off","When app dictation is not configured","In every app"},SelectedIndex=(int)controller.Config.VoiceTyping.Mode,Margin=new Padding(0,0,0,16)};
        var bindings=controller.Config.Bindings.Where(b=>b.ControlID!=null).ToArray();
        var button=new ComboBox{DropDownStyle=ComboBoxStyle.DropDownList,Width=540,DataSource=bindings.Select(b=>b.Name).ToArray(),Margin=new Padding(0,0,0,16)};
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
internal sealed class AddRemoteFlow:Form
{
    public string? SelectedPluginID { get; private set; }
    public AddRemoteFlow(PluginCatalog catalog)
    {
        Text="Add a remote";ClientSize=new Size(840,640);MinimumSize=new Size(760,560);StartPosition=FormStartPosition.CenterParent;Font=WorkspaceStyle.Text();AutoScaleMode=AutoScaleMode.Dpi;BackColor=Palette.Background;
        var root=new TableLayoutPanel{Dock=DockStyle.Fill,Padding=new Padding(28),RowCount=4,ColumnCount=1};root.RowStyles.Add(new(SizeType.Absolute,112));root.RowStyles.Add(new(SizeType.Percent,100));root.RowStyles.Add(new(SizeType.Absolute,72));root.RowStyles.Add(new(SizeType.Absolute,112));Controls.Add(root);
        var header=WorkspaceStyle.Stack();header.Controls.Add(WorkspaceStyle.Label("Add your remote",20,true,true));header.Controls.Add(WorkspaceStyle.Label("Pair in Windows Bluetooth settings or connect its USB receiver, then refresh. Select a supported identity to open its setup.",10,false,false,760));root.Controls.Add(header,0,0);
        var list=new ListBox{Dock=DockStyle.Fill,HorizontalScrollbar=true,IntegralHeight=false,AccessibleName="Connected input devices"};root.Controls.Add(list,0,1);
        var status=WorkspaceStyle.Label("",9,false,false,760);status.Dock=DockStyle.Fill;root.Controls.Add(status,0,2);
        var devices=new List<(string Path,string? Plugin)>();
        void RefreshDevices()
        {
            list.Items.Clear();devices.Clear();
            foreach(var path in NativeInput.Discover())
            {
                var matches=catalog.Devices.Where(d=>ReceiverDecoder.Matches(path,d.Device!.Profile)).ToArray();
                devices.Add((path,matches.Length==1?matches[0].Id:null));list.Items.Add((matches.Length==1?matches[0].Name:matches.Length>1?"Ambiguous receiver profiles":"Unidentified input device")+" · "+path);
            }
            status.Text="A device path is identity evidence, not proof of button or microphone support. Unknown devices can use the agent setup prompt.";
        }
        root.Controls.Add(WorkspaceStyle.Row(WorkspaceStyle.Button("Bluetooth settings",()=>WorkspaceStyle.Open("ms-settings:bluetooth")),WorkspaceStyle.Button("Refresh",RefreshDevices),WorkspaceStyle.Button("Get agent setup prompt",()=>{
            var identity=list.SelectedIndex>=0?devices[list.SelectedIndex].Path:"No device selected";
            Clipboard.SetText("Help me identify my remote in JustVibe Remote on Windows. Ask for the model and a clear front photo. Use read-only receiver evidence; do not guess VID/PID, usages, or microphone transport. Check installed support before creating a plugin. Follow AGENTS.md and the PluginAuthoring guides. Observed interface: "+identity);
            status.Text="Setup prompt copied. Attach a clear front photo in your coding chat. Open the starter folder for guides.";
        }),WorkspaceStyle.Button("Starter and guides",()=>WorkspaceStyle.Open(Path.Combine(AppContext.BaseDirectory,"PluginAuthoring"))),WorkspaceStyle.Button("Open remote",()=>{if(list.SelectedIndex>=0&&devices[list.SelectedIndex].Plugin is {} id){SelectedPluginID=id;DialogResult=DialogResult.OK;}else status.Text="Select an interface with one matching installed plugin. Otherwise use the setup prompt.";},true)),0,3);
        if(root.GetControlFromPosition(0,3) is FlowLayoutPanel footer)footer.MaximumSize=new Size(680,0);
        RefreshDevices();WorkspaceStyle.Apply(this);
    }
}
