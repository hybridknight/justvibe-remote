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
    private readonly WorkspacePicker devices=new(){DropDownStyle=ComboBoxStyle.DropDownList,Width=240};
    private readonly WorkspacePicker apps=new(){DropDownStyle=ComboBoxStyle.DropDownList,Width=240,AccessibleName="App profile"};
    private readonly CheckBox followApp=new(){Text="Follow active app",AutoSize=true};
    private readonly Label routeLabel=MakeLabel("",9),actionContext=MakeLabel("",12,true);
    private readonly WorkspacePicker bindingPicker=new(){DropDownStyle=ComboBoxStyle.DropDownList,Width=460,AccessibleName="Remote button"};
    private readonly WorkspacePicker actionPicker=new(){DropDownStyle=ComboBoxStyle.DropDownList,Width=460,AccessibleName="Button action"};
    private readonly Label selectedName=MakeLabel("Microphone",26,true),linked=MakeLabel("Not linked yet",10),hint=Block(""),learningHelp=Block(""),actionHelp=Block(""),status=Block(""),progress=MakeLabel("",9),badge=MakeLabel("Not connected",10),target=Block(""),signal=Block("");
    private readonly Label microphoneStatus=Block("");
    private readonly ShortcutRecorder shortcut=new(){Width=320};
    private readonly CheckBox confirmed=new(){Text="Matches my app’s hold-to-dictate shortcut",AutoSize=true},toggle=new(){Text="Press once to start, again to stop",AutoSize=true};
    private readonly FlowLayoutPanel voice=Stack(),advanced=Stack();
    private RemoteMappingBoard mappingBoard=null!;
    private AppProfileSelector appProfiles=null!;
    private readonly Label dictationBinding=MakeLabel("Not configured",14,true),dictationBindingHelp=Block("");
    private WorkspaceButton connect=null!,learn=null!,cancel=null!,stopVoice=null!,launchAppButton=null!;
    private bool loading;private int selectedIndex;private string bindingSignature="",actionSignature="";
    public MainWindow(string? verificationSettings=null)
    {
        sessions=new RemoteSessions(verificationSettings);
        controller=sessions.Initial??(verificationSettings==null?new RemoteController():new RemoteController(new ConfigurationStore(Path.Combine(verificationSettings,"settings.json"))));
        var area=Screen.PrimaryScreen?.WorkingArea??new Rectangle(0,0,1920,1080);
        Text="JustVibe Remote";ClientSize=new Size(Math.Min(1400,area.Width-40),Math.Min(940,area.Height-80));MinimumSize=new Size(Math.Min(1200,area.Width-40),Math.Min(840,area.Height-80));StartPosition=FormStartPosition.CenterScreen;
        Font=WorkspaceStyle.Text();BackColor=Palette.Background;AutoScaleMode=AutoScaleMode.Dpi;KeyPreview=true;
        // These selectors also refresh while their page is detached. Give them
        // a stable binding context before assigning data or selecting an item.
        foreach(var picker in new[]{devices,apps,bindingPicker,actionPicker})picker.BindingContext=BindingContext;
        BuildWorkspace();PopulatePlugins();LoadEditable();
        devices.SelectedIndexChanged+=(_,_)=>SelectPlugins();apps.SelectedIndexChanged+=(_,_)=>SelectPlugins();
        bindingPicker.SelectedIndexChanged+=(_,_)=>{if(loading||bindingPicker.SelectedIndex<0)return;selectedIndex=bindingPicker.SelectedIndex;controller.CancelLearning();RefreshState();};
        actionPicker.SelectionChangeCommitted+=(_,_)=>{if(!loading)CommitSelectedAction();};
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
    private static WorkspaceButton Button(string text,Action action,bool primary=false)=>WorkspaceStyle.Button(text,action,primary);
    private sealed record ActionChoice(ActionKind Action,string Title);
    internal static string ActionTitle(ActionKind action)=>action switch{ActionKind.Native=>"Keep original action",ActionKind.Dictate=>"Dictation",ActionKind.Focus=>"Open app",ActionKind.Send=>"Send (Return)",ActionKind.Backspace=>"Delete previous character",_=>"Escape"};
    private void LoadEditable(){loading=true;shortcut.Text=controller.Config.Shortcut;confirmed.Checked=controller.Config.ShortcutConfirmed;toggle.Checked=controller.Config.VoiceMode=="toggle";loading=false;}
    private void RefreshState()
    {
        if(IsDisposed||loading)return;
        if(selectedIndex>=controller.Config.Bindings.Count)selectedIndex=0;loading=true;var binding=controller.Config.Bindings[selectedIndex];var signature=string.Join('|',controller.Config.Bindings.Select(b=>b.ControlID+b.Name));
        if(signature!=bindingSignature){bindingPicker.DataSource=controller.Config.Bindings.Select(b=>b.Name).ToArray();bindingSignature=signature;}bindingPicker.SelectedIndex=selectedIndex;
        followApp.Checked=controller.Config.FollowActiveApp;routeLabel.Text=controller.Config.FollowActiveApp?(controller.Running?controller.RoutingLabel:"Connect remote to follow active app"):"Use only the selected app’s mappings";
        actionContext.Text="ACTION";launchAppButton.Visible=binding.Action==ActionKind.Focus;
        selectedName.Text=binding.Name;linked.Text=binding.Usage==null?"Not linked yet":"Linked to your remote";linked.ForeColor=binding.Usage==null?Palette.Muted:Palette.Teal;
        var item=controller.Layout.Buttons.FirstOrDefault(b=>b.Id==binding.ControlID);hint.Text=item?.Hint??"";hint.Visible=hint.Text.Length>0;
        bool learning=controller.LearningIndex==selectedIndex;learn.Text=learning?"Press remote button…":binding.Usage==null?"Link button":"Relink button";learn.Enabled=!learning;cancel.Visible=learning;
        learningHelp.Text=learning?$"Press {binding.Name} on your remote. Saved actions pause while linking.":binding.Usage==null?"Link this control once to use its custom action.":"Linked. Use Learn again to replace this button’s signal.";
        var actions=controller.AvailableActions;string nextActions=string.Join('|',actions);
        if(nextActions!=actionSignature){actionPicker.DisplayMember="Title";actionPicker.DataSource=actions.Select(action=>new ActionChoice(action,ActionTitle(action))).ToList();actionSignature=nextActions;}
        if(actionPicker.SelectedItem is not ActionChoice selectedAction||selectedAction.Action!=binding.Action)actionPicker.SelectedItem=((List<ActionChoice>)actionPicker.DataSource!).FirstOrDefault(choice=>choice.Action==binding.Action);
        actionHelp.Text=binding.Action==ActionKind.Native?"Keeps the remote’s normal behavior. Choose an action to personalize it.":binding.Usage==null?"Action saved. Link this button to activate it.":$"Saved for {controller.AppPlugin?.Name??"all other apps"}.";
        if(binding.Action==ActionKind.Focus)actionHelp.Text=$"Open {controller.Catalog.Apps.FirstOrDefault(p=>p.Id==(binding.LaunchAppID??controller.Config.AppPluginID))?.Name??"an unavailable app"} when you press {binding.Name}. A running app is brought to the front."+(binding.Usage==null?" Link this button first.":"");
        if(binding.Action==ActionKind.Focus&&binding.LaunchApps is {Count:>1} targets)actionHelp.Text="Cycle on each press: "+string.Join(" → ",targets.Select(t=>controller.Catalog.Apps.FirstOrDefault(p=>p.Id==t.Id)?.Name??"Unavailable app"))+" → repeat.";
        microphoneStatus.Text=controller.MicrophoneSummary;
        voice.Visible=binding.Action==ActionKind.Dictate&&controller.AppPlugin?.App?.Supports(ActionKind.Dictate)==true;signal.Text=binding.Usage is Usage u?$"Button signal: {u}":"Button signal: not learned";
        dictationBinding.Text=string.IsNullOrWhiteSpace(controller.Config.Shortcut)?"Not configured":controller.Config.Shortcut;
        dictationBinding.ForeColor=Palette.Accent;
        dictationBindingHelp.Text=controller.Config.ShortcutConfirmed?"Confirmed for this app.":"Match and confirm your app’s dictation shortcut in voice settings.";
        target.Text=controller.Config.AppPluginID==Configuration.NoSpecificAppID?"Shared controls work in the app you are using.":controller.Config.TargetAppPath.Length==0?$"App connection: use the running {controller.AppPlugin?.Name??"selected app"}.":$"App connection: {Path.GetFileName(controller.Config.TargetAppPath)}";
        canvas.UpdateRemote(controller.Layout,controller.Config.Bindings,binding.ControlID??$"button-{selectedIndex}",controller.ActiveUsages);
        mappingBoard.UpdateRemote(controller.Layout,controller.Config.Bindings,binding.ControlID??$"button-{selectedIndex}",actions,controller.LearningIndex,controller.ActiveUsages,controller.Config.Shortcut,controller.Catalog.Apps,controller.Config.AppPluginID);
        appProfiles.UpdateChoices(new[]{NativeProfile}.Concat(controller.Catalog.Apps),controller.Config);
        int linkedCount=controller.Layout.Buttons.Count(item=>controller.Config.Bindings.Any(b=>b.ControlID==item.Id&&b.Usage!=null));progress.Text=$"{linkedCount} of {controller.Layout.Buttons.Count} buttons linked";
        badge.Text=controller.Running?controller.Connected>0?"Connected":"Looking for remote…":"Not connected";badge.ForeColor=controller.Connected>0?Palette.Teal:Palette.Muted;connect.Text=controller.Running?"Disconnect":"Connect remote";stopVoice.Visible=sessions.Controllers.Values.Any(session=>session.VoiceActive)||controller.VoiceActive;
        status.Text=controller.Status.StartsWith("Learned ")?$"{binding.Name} linked. Choose what it does above.":controller.Status;bindingPicker.Parent?.PerformLayout();loading=false;refreshPage?.Invoke();
    }
    private void CommitSelectedAction()
    {
        if(actionPicker.SelectedItem is not ActionChoice choice)return;
        AssignSelectedAction(choice.Action);
    }
    private void AssignSelectedAction(ActionKind action)
    {
        if(action==ActionKind.Focus){ChooseLaunchApp();return;}
        Try(()=>{var bindings=controller.Config.Bindings.ToList();bindings[selectedIndex]=bindings[selectedIndex] with{Action=action,LaunchAppID=null,LaunchAppPath=null,LaunchApps=null};controller.Update(controller.Config with{Bindings=bindings});});
    }
    private void SelectControl(string id){int index=controller.Config.Bindings.FindIndex(b=>b.ControlID==id);if(index<0&&id.StartsWith("button-"))int.TryParse(id[7..],out index);if(index>=0&&index<controller.Config.Bindings.Count)selectedIndex=index;controller.CancelLearning();RefreshState();}
    private void TestMicrophone(){sessions.StopVoices();using var test=new MicrophoneTest(controller);test.ShowDialog(this);RefreshState();}
    private void OpenQuickSetup(){sessions.StopVoices();using var setup=new QuickSetup(controller);setup.ShowDialog(this);PopulatePlugins();LoadEditable();ShowPage(currentPage);}
    private void Connect(){if(controller.Running)Try(controller.Stop);else controller.Start();}
    private void Learn(){if(!controller.Running)controller.Start();if(controller.Running)controller.Learn(selectedIndex);}
    private void SaveVoice(){SaveVoiceSettings();}
    private bool SaveVoiceSettings(){try{controller.Update(controller.Config with{Shortcut=shortcut.Text,ShortcutConfirmed=confirmed.Checked,VoiceMode=toggle.Checked?"toggle":"hold"});return true;}catch(Exception error){ShowError(error);return false;}}
    private void TryVoice(){if(controller.VoiceActive){controller.StopVoice();return;}if(!SaveVoiceSettings())return;if(!controller.Running)controller.Start();controller.TestVoice();}
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
