using JustVibeRemote.Core;

namespace JustVibeRemote;
internal static class Program
{
    [STAThread]private static void Main(string[] args)
    {
        if(args.Length==2&&args[0]=="--verify-ui")
        {
            ApplicationConfiguration.Initialize();
            try{WorkspaceVerification.Run(Path.GetFullPath(args[1]));}catch(Exception error){Environment.ExitCode=1;try{Directory.CreateDirectory(Path.GetFullPath(args[1]));File.WriteAllText(Path.Combine(Path.GetFullPath(args[1]),"failure.txt"),error.ToString());}catch{System.Diagnostics.Trace.WriteLine(error);}}
            return;
        }
        using var singleton=new Mutex(true,"Local\\JustVibeRemote",out bool first);
        if(!first){MessageBox.Show("JustVibe Remote is already running.","JustVibe Remote");return;}
        ApplicationConfiguration.Initialize();
        try{Application.Run(new MainWindow());}catch(Exception error){MessageBox.Show(error.Message,"JustVibe Remote could not start",MessageBoxButtons.OK,MessageBoxIcon.Error);}
    }
}
internal sealed partial class MainWindow:Form
{
    private RemoteController controller=null!;
    private readonly RemoteSessions sessions;
    private readonly RemoteCanvas canvas=new(){Dock=DockStyle.Fill};
    private readonly ComboBox devices=new(){DropDownStyle=ComboBoxStyle.DropDownList,Width=240};
    private readonly ComboBox apps=new(){DropDownStyle=ComboBoxStyle.DropDownList,Width=170};
    private readonly CheckBox followApp=new(){Text="Follow active app",AutoSize=true};
    private readonly Label routeLabel=MakeLabel("",9),actionContext=MakeLabel("",12,true);
    private readonly ComboBox bindingPicker=new(){DropDownStyle=ComboBoxStyle.DropDownList,Width=460};
    private readonly ComboBox actionPicker=new(){DropDownStyle=ComboBoxStyle.DropDownList,Width=460};
    private readonly Label selectedName=MakeLabel("Microphone",26,true),linked=MakeLabel("Not linked yet",10),hint=Block(""),learningHelp=Block(""),actionHelp=Block(""),status=Block(""),progress=MakeLabel("",9),badge=MakeLabel("Not connected",10),target=Block(""),signal=Block("");
    private readonly Label microphoneStatus=Block("");
    private readonly ShortcutRecorder shortcut=new(){Width=320};
    private readonly CheckBox confirmed=new(){Text="Matches my app’s hold-to-dictate shortcut",AutoSize=true},toggle=new(){Text="Press once to start, again to stop",AutoSize=true};
    private readonly FlowLayoutPanel voice=Stack(),advanced=Stack();
    private Button connect=null!,learn=null!,cancel=null!,stopVoice=null!,launchAppButton=null!;
    private bool loading;private int selectedIndex;private string bindingSignature="";
    public MainWindow(string? verificationSettings=null)
    {
        sessions=new RemoteSessions(verificationSettings);
        controller=sessions.Initial??(verificationSettings==null?new RemoteController():new RemoteController(new ConfigurationStore(Path.Combine(verificationSettings,"settings.json"))));
        Text="JustVibe Remote";ClientSize=new Size(1380,940);MinimumSize=new Size(1200,840);StartPosition=FormStartPosition.CenterScreen;
        Font=WorkspaceStyle.Text();BackColor=Palette.Background;AutoScaleMode=AutoScaleMode.Dpi;KeyPreview=true;
        BuildWorkspace();PopulatePlugins();LoadEditable();
        devices.SelectedIndexChanged+=(_,_)=>SelectPlugins();apps.SelectedIndexChanged+=(_,_)=>SelectPlugins();
        bindingPicker.SelectedIndexChanged+=(_,_)=>{if(loading||bindingPicker.SelectedIndex<0)return;selectedIndex=bindingPicker.SelectedIndex;controller.CancelLearning();RefreshState();};
        actionPicker.SelectionChangeCommitted+=(_,_)=>{if(loading||actionPicker.SelectedItem is not ActionChoice choice)return;if(choice.Action==ActionKind.Focus){ChooseLaunchApp();return;}Try(()=>{var bindings=controller.Config.Bindings.ToList();bindings[selectedIndex]=bindings[selectedIndex] with{Action=choice.Action,LaunchAppID=null,LaunchAppPath=null};controller.Update(controller.Config with{Bindings=bindings});});};
        followApp.CheckedChanged+=(_,_)=>{if(!loading)Try(()=>controller.Update(controller.Config with{FollowActiveApp=followApp.Checked}));};
        sessions.Changed+=RefreshState;
        Shown+=(_,_)=>{if(verificationSettings==null)sessions.Activate();ShowPage(WorkspacePage.Remotes);};
        FormClosing+=(_,e)=>{try{sessions.Dispose();if(sessions.Initial==null)controller.Dispose();}catch(Exception error){e.Cancel=true;ShowError(error);}};
        Activated+=(_,_)=>controller.SetButtonTest(currentPage==WorkspacePage.ButtonTest);
        Deactivate+=(_,_)=>controller.SetButtonTest(false);
        KeyDown+=(_,e)=>{if(e.Control&&e.KeyCode>=Keys.D1&&e.KeyCode<=Keys.D8){var pages=new[]{WorkspacePage.Remotes,WorkspacePage.Overview,WorkspacePage.Apps,WorkspacePage.Buttons,WorkspacePage.Microphone,WorkspacePage.Settings,WorkspacePage.Plugins,WorkspacePage.Help};ShowPage(pages[(int)e.KeyCode-(int)Keys.D1]);e.Handled=true;}};
        WorkspaceStyle.Apply(this);ShowPage(WorkspacePage.Remotes);RefreshState();
    }
    private static Label MakeLabel(string text,float size,bool bold=false)=>WorkspaceStyle.Label(text,size,bold,bold&&size>=12);
    private static Label Block(string text){var value=MakeLabel(text,10);value.MaximumSize=new Size(470,0);return value;}
    private static Control Section(string title){var value=MakeLabel(title,12,true);value.Margin=new Padding(0,WorkspaceStyle.Section,0,WorkspaceStyle.Controls);return value;}
    private static FlowLayoutPanel Stack()=>WorkspaceStyle.Stack();
    private static Control Row(params Control[] children)=>WorkspaceStyle.Row(children);
    private static Panel Card()=>new RoundedCard{Dock=DockStyle.Fill,Padding=new Padding(2)};
    private static Button Button(string text,Action action,bool primary=false)=>WorkspaceStyle.Button(text,action,primary);
    private sealed record ActionChoice(ActionKind Action,string Title);
    private static string ActionTitle(ActionKind action)=>action switch{ActionKind.Native=>"Keep original action",ActionKind.Dictate=>"Dictation",ActionKind.Focus=>"Open app",ActionKind.Send=>"Send (Return)",ActionKind.Backspace=>"Delete previous character",_=>"Escape"};
    private void LoadEditable(){loading=true;shortcut.Text=controller.Config.Shortcut;confirmed.Checked=controller.Config.ShortcutConfirmed;toggle.Checked=controller.Config.VoiceMode=="toggle";loading=false;}
    private void RefreshState()
    {
        if(IsDisposed||loading)return;
        if(selectedIndex>=controller.Config.Bindings.Count)selectedIndex=0;loading=true;var binding=controller.Config.Bindings[selectedIndex];var signature=string.Join('|',controller.Config.Bindings.Select(b=>b.ControlID+b.Name));
        if(signature!=bindingSignature){bindingPicker.DataSource=controller.Config.Bindings.Select(b=>b.Name).ToArray();bindingSignature=signature;}bindingPicker.SelectedIndex=selectedIndex;
        followApp.Checked=controller.Config.FollowActiveApp;routeLabel.Text=controller.Config.FollowActiveApp?(controller.Running?controller.RoutingLabel:"Connect remote to follow active app"):"Use only the selected app’s mappings";
        actionContext.Text="Action";launchAppButton.Visible=binding.Action==ActionKind.Focus;
        selectedName.Text=binding.Name;linked.Text=binding.Usage==null?"Not linked yet":"Linked to your remote";linked.ForeColor=binding.Usage==null?Palette.Muted:Palette.Teal;
        var item=controller.Layout.Buttons.FirstOrDefault(b=>b.Id==binding.ControlID);hint.Text=item?.Hint??"Select a button on the remote, then link it to the matching physical button.";
        bool learning=controller.LearningIndex==selectedIndex;learn.Text=learning?"Waiting for your remote…":binding.Usage==null?"Learn this button":"Learn again";learn.Enabled=!learning;cancel.Visible=learning;
        learningHelp.Text=learning?$"Press only {binding.Name} on your physical remote. JustVibe Remote won’t run your saved action while learning.":"Learning identifies a button’s signal. It doesn’t trigger its assigned action.";
        var actionChoices=controller.AvailableActions.Select(action=>new ActionChoice(action,ActionTitle(action))).ToList();actionPicker.DisplayMember="Title";actionPicker.DataSource=actionChoices;actionPicker.SelectedItem=actionChoices.FirstOrDefault(choice=>choice.Action==binding.Action);actionHelp.Text=binding.Action==ActionKind.Native?"Keeps the remote’s normal behavior. Choose an action to personalize it.":binding.Usage==null?"Action selected. Learn this button to activate the mapping.":$"Saved for {controller.AppPlugin?.Name??"this app"}. Other app profiles keep their own actions.";
        if(binding.Action==ActionKind.Focus)actionHelp.Text=$"Open {controller.Catalog.Apps.FirstOrDefault(p=>p.Id==(binding.LaunchAppID??controller.Config.AppPluginID))?.Name??"an unavailable app"} when you press {binding.Name}. A running app is brought to the front."+(binding.Usage==null?" Link this button first.":"");
        microphoneStatus.Text=controller.MicrophoneSummary;
        voice.Visible=binding.Action==ActionKind.Dictate&&controller.AppPlugin?.App?.Supports(ActionKind.Dictate)==true;signal.Text=binding.Usage is Usage u?$"Button signal: {u}":"Button signal: not learned";
        target.Text=controller.Config.TargetAppPath.Length==0?$"App connection: use the running {controller.AppPlugin?.Name??"selected app"}.":$"App connection: {Path.GetFileName(controller.Config.TargetAppPath)}";
        canvas.UpdateRemote(controller.Layout,controller.Config.Bindings,binding.ControlID??$"button-{selectedIndex}",controller.ActiveUsages);
        int linkedCount=controller.Layout.Buttons.Count(item=>controller.Config.Bindings.Any(b=>b.ControlID==item.Id&&b.Usage!=null));progress.Text=$"{linkedCount} of {controller.Layout.Buttons.Count} buttons linked · {(controller.DevicePlugin?.Device?.Layout==null?"generic layout":"photo-based layout")}";
        badge.Text=controller.Running?controller.Connected>0?"Connected":"Looking for remote…":"Not connected";badge.ForeColor=controller.Connected>0?Palette.Teal:Palette.Muted;connect.Text=controller.Running?"Disconnect":"Connect remote";stopVoice.Visible=sessions.Controllers.Values.Any(session=>session.VoiceActive)||controller.VoiceActive;
        status.Text=controller.Status.StartsWith("Learned ")?$"{binding.Name} linked. Choose what it does above.":controller.Status;loading=false;refreshPage?.Invoke();
    }
    private void SelectControl(string id){int index=controller.Config.Bindings.FindIndex(b=>b.ControlID==id);if(index<0&&id.StartsWith("button-"))int.TryParse(id[7..],out index);if(index>=0&&index<controller.Config.Bindings.Count)selectedIndex=index;controller.CancelLearning();RefreshState();}
    private void TestMicrophone(){sessions.StopVoices();using var test=new MicrophoneTest(controller);test.ShowDialog(this);RefreshState();}
    private void OpenQuickSetup(){sessions.StopVoices();using var setup=new QuickSetup(controller);setup.ShowDialog(this);PopulatePlugins();LoadEditable();ShowPage(currentPage);}
    private void Connect(){if(controller.Running)Try(controller.Stop);else controller.Start();}
    private void Learn(){if(!controller.Running)controller.Start();if(controller.Running)controller.Learn(selectedIndex);}
    private void SaveVoice(){SaveVoiceSettings();}
    private bool SaveVoiceSettings(){try{controller.Update(controller.Config with{Shortcut=shortcut.Text,ShortcutConfirmed=confirmed.Checked,VoiceMode=toggle.Checked?"toggle":"hold"});return true;}catch(Exception error){ShowError(error);return false;}}
    private void TryVoice(){if(controller.VoiceActive){controller.StopVoice();return;}if(!controller.Running){controller.TestVoice();return;}if(SaveVoiceSettings())controller.TestVoice();}
    private static PluginManifest NativeProfile=>new(){Id=Configuration.NoSpecificAppID,Name="No specific app"};
    private void PopulatePlugins()
    {
        loading=true;
        devices.DataSource=sessions.Catalog.Devices.ToList();devices.DisplayMember="Name";devices.SelectedItem=sessions.Catalog.Devices.FirstOrDefault(p=>p.Id==controller.Config.DevicePluginID);
        var choices=new[]{NativeProfile}.Concat(controller.Catalog.Apps).ToList();apps.DataSource=choices;apps.DisplayMember="Name";apps.SelectedItem=choices.FirstOrDefault(p=>p.Id==controller.Config.AppPluginID);loading=false;
    }
    private void SelectPlugins()
    {
        if(loading||devices.SelectedItem is not PluginManifest d||apps.SelectedItem is not PluginManifest a)return;
        Try(()=>{
            if(d.Id!=controller.Config.DevicePluginID){SelectRemote(d.Id);return;}
            controller.SelectPlugins(d.Id,a.Id);selectedIndex=0;LoadEditable();RefreshState();
        });
    }
    private void ChooseTarget(){using var dialog=new OpenFileDialog{Filter="Application (*.exe)|*.exe",Title="Choose the target application"};if(dialog.ShowDialog(this)==DialogResult.OK)Try(()=>controller.Update(controller.Config with{TargetAppPath=dialog.FileName}));}
    private void ManagePlugins()=>ShowPage(WorkspacePage.Plugins);
    private void Try(Action action){try{action();}catch(Exception error){ShowError(error);}}
    private void ShowError(Exception error)=>MessageBox.Show(this,error.Message,"JustVibe Remote",MessageBoxButtons.OK,MessageBoxIcon.Information);
}
