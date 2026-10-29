using JustVibeRemote.Core;

namespace JustVibeRemote;
internal static class Program
{
    [STAThread]private static void Main()
    {
        using var singleton=new Mutex(true,"Local\\JustVibeRemote",out bool first);
        if(!first){MessageBox.Show("JustVibe Remote is already running.","JustVibe Remote");return;}
        ApplicationConfiguration.Initialize();
        try{Application.Run(new MainWindow());}catch(Exception error){MessageBox.Show(error.Message,"JustVibe Remote could not start",MessageBoxButtons.OK,MessageBoxIcon.Error);}
    }
}
internal sealed class MainWindow:Form
{
    private readonly RemoteController controller=new();
    private readonly RemoteCanvas canvas=new(){Dock=DockStyle.Fill};
    private readonly ComboBox devices=new(){DropDownStyle=ComboBoxStyle.DropDownList,Width=240};
    private readonly ComboBox apps=new(){DropDownStyle=ComboBoxStyle.DropDownList,Width=170};
    private readonly CheckBox followApp=new(){Text="Follow active app",AutoSize=true};
    private readonly Label routeLabel=MakeLabel("",9),actionContext=MakeLabel("",12,true);
    private readonly ComboBox bindingPicker=new(){DropDownStyle=ComboBoxStyle.DropDownList,Width=460};
    private readonly ComboBox actionPicker=new(){DropDownStyle=ComboBoxStyle.DropDownList,Width=460};
    private readonly Label selectedName=MakeLabel("Microphone",26,true),linked=MakeLabel("Not linked yet",10),hint=Block(""),learningHelp=Block(""),actionHelp=Block(""),status=Block(""),progress=MakeLabel("",9),badge=MakeLabel("Not connected",10),target=Block(""),signal=Block("");
    private readonly Label microphoneStatus=Block("");
    private readonly TextBox shortcut=new(){Width=165};
    private readonly CheckBox confirmed=new(){Text="Matches my app’s hold-to-dictate shortcut",AutoSize=true},toggle=new(){Text="Press once to start, again to stop",AutoSize=true};
    private readonly FlowLayoutPanel voice=Stack(),advanced=Stack();
    private Button connect=null!,learn=null!,cancel=null!,stopVoice=null!;
    private bool loading;private int selectedIndex;private string bindingSignature="";
    public MainWindow()
    {
        Text="JustVibe Remote";ClientSize=new Size(1160,860);MinimumSize=new Size(1020,800);StartPosition=FormStartPosition.CenterScreen;Font=new Font("Segoe UI",10);BackColor=Palette.Background;AutoScaleMode=AutoScaleMode.Dpi;
        var root=new TableLayoutPanel{Dock=DockStyle.Fill,RowCount=4,ColumnCount=1,Padding=new Padding(24),BackColor=Palette.Background};root.RowStyles.Add(new(SizeType.Absolute,74));root.RowStyles.Add(new(SizeType.Absolute,116));root.RowStyles.Add(new(SizeType.Percent,100));root.RowStyles.Add(new(SizeType.Absolute,56));Controls.Add(root);
        var header=new TableLayoutPanel{Dock=DockStyle.Fill,ColumnCount=2};header.ColumnStyles.Add(new(SizeType.Percent,55));header.ColumnStyles.Add(new(SizeType.Percent,45));
        using(var iconStream=typeof(MainWindow).Assembly.GetManifestResourceStream("JustVibeRemote.Branding.ico"))
            if(iconStream is not null) { using var icon=new Icon(iconStream); Icon=(Icon)icon.Clone(); }
        var titles=Stack();titles.Controls.Add(MakeLabel("JustVibe Remote",25,true));titles.Controls.Add(MakeLabel("Make every button yours.",10));
        var brand=new PictureBox{Size=new Size(60,60),SizeMode=PictureBoxSizeMode.Zoom,Margin=new Padding(0,0,10,0)};
        using(var artworkStream=typeof(MainWindow).Assembly.GetManifestResourceStream("JustVibeRemote.Branding.png"))
            if(artworkStream is not null) { using var image=Image.FromStream(artworkStream); brand.Image=new Bitmap(image); }
        var identity=new FlowLayoutPanel{Dock=DockStyle.Fill,WrapContents=false,Margin=Padding.Empty};identity.Controls.Add(brand);identity.Controls.Add(titles);header.Controls.Add(identity,0,0);
        Disposed+=(_,_)=>{brand.Image?.Dispose();Icon?.Dispose();};
        var headerActions=new FlowLayoutPanel{Dock=DockStyle.Fill,FlowDirection=FlowDirection.RightToLeft,WrapContents=false};connect=Button("Connect remote",Connect,true);stopVoice=Button("Stop voice",controller.StopVoice);stopVoice.Visible=false;headerActions.Controls.Add(connect);headerActions.Controls.Add(Button("Quick setup",OpenQuickSetup));headerActions.Controls.Add(stopVoice);headerActions.Controls.Add(badge);header.Controls.Add(headerActions,1,0);root.Controls.Add(header,0,0);
        var selectors=Card();selectors.Margin=new Padding(0,0,0,12);var selectionRow=new FlowLayoutPanel{Dock=DockStyle.Top,Height=54,WrapContents=false,Padding=new Padding(14,10,14,8),BackColor=Color.White};selectionRow.Controls.Add(MakeLabel("REMOTE",9,true));selectionRow.Controls.Add(devices);selectionRow.Controls.Add(MakeLabel("EDIT APP",9,true));selectionRow.Controls.Add(apps);selectionRow.Controls.Add(Button("Plugins…",ManagePlugins));var routeRow=new FlowLayoutPanel{Dock=DockStyle.Bottom,Height=36,Padding=new Padding(14,0,14,0),WrapContents=false,BackColor=Color.White};routeRow.Controls.Add(followApp);routeRow.Controls.Add(routeLabel);routeRow.Controls.Add(Button("Microphone test…",TestMicrophone));selectors.Controls.Add(routeRow);selectors.Controls.Add(selectionRow);root.Controls.Add(selectors,0,1);
        var columns=new TableLayoutPanel{Dock=DockStyle.Fill,ColumnCount=2,RowCount=1,Margin=Padding.Empty};columns.ColumnStyles.Add(new(SizeType.Percent,40));columns.ColumnStyles.Add(new(SizeType.Percent,60));root.Controls.Add(columns,0,2);
        var remote=Card();remote.Margin=new Padding(0,0,9,0);var remoteHeader=Stack();remoteHeader.Dock=DockStyle.Top;remoteHeader.Height=65;remoteHeader.AutoSize=false;remoteHeader.Padding=new Padding(20,16,20,0);remoteHeader.Controls.Add(MakeLabel("YOUR REMOTE",9,true));remoteHeader.Controls.Add(MakeLabel("Click a button to configure it",12,true));
        progress.Dock=DockStyle.Bottom;progress.Height=36;progress.TextAlign=ContentAlignment.MiddleCenter;progress.AutoSize=false;remote.Controls.Add(canvas);remote.Controls.Add(remoteHeader);remote.Controls.Add(progress);columns.Controls.Add(remote,0,0);canvas.Selected+=SelectControl;
        var inspector=Card();inspector.Margin=new Padding(9,0,0,0);var form=Stack();form.Dock=DockStyle.Fill;form.AutoSize=false;form.AutoScroll=true;form.Padding=new Padding(24,20,24,20);inspector.Controls.Add(form);columns.Controls.Add(inspector,1,0);
        form.Controls.Add(MakeLabel("BUTTON SETTINGS",9,true));form.Controls.Add(bindingPicker);form.Controls.Add(selectedName);form.Controls.Add(linked);form.Controls.Add(hint);
        learn=Button("Learn this button",Learn,true);cancel=Button("Cancel",controller.CancelLearning);cancel.Visible=false;form.Controls.Add(Row(learn,cancel));form.Controls.Add(learningHelp);
        form.Controls.Add(actionContext);form.Controls.Add(actionPicker);form.Controls.Add(actionHelp);
        voice.Controls.Add(Section("Voice setup"));voice.Controls.Add(Button("Test microphone…",TestMicrophone));voice.Controls.Add(microphoneStatus);voice.Controls.Add(Block("Choose the remote’s USB microphone in your app, then match its hold-to-dictate shortcut below."));voice.Controls.Add(Row(shortcut,Button("Save voice settings",SaveVoice)));voice.Controls.Add(confirmed);voice.Controls.Add(toggle);voice.Controls.Add(Row(Button("Try dictation",TryVoice),Button("Locate app…",ChooseTarget)));form.Controls.Add(voice);
        form.Controls.Add(target);form.Controls.Add(Button("Advanced & app connection",()=>{advanced.Visible=!advanced.Visible;}));advanced.Controls.Add(signal);advanced.Controls.Add(Block("Windows keeps native remote actions. Custom actions run alongside them. Keep ordinary typing and navigation native to avoid duplicate input."));advanced.Controls.Add(Button("Locate app…",ChooseTarget));advanced.Visible=false;form.Controls.Add(advanced);
        var footer=new TableLayoutPanel{Dock=DockStyle.Fill,ColumnCount=2};footer.ColumnStyles.Add(new(SizeType.Percent,72));footer.ColumnStyles.Add(new(SizeType.Percent,28));status.Dock=DockStyle.Fill;status.MaximumSize=Size.Empty;footer.Controls.Add(status,0,0);footer.Controls.Add(MakeLabel("Button actions save automatically",9),1,0);root.Controls.Add(footer,0,3);
        PopulatePlugins();LoadEditable();devices.SelectedIndexChanged+=(_,_)=>SelectPlugins();apps.SelectedIndexChanged+=(_,_)=>SelectPlugins();
        bindingPicker.SelectedIndexChanged+=(_,_)=>{if(loading||bindingPicker.SelectedIndex<0)return;selectedIndex=bindingPicker.SelectedIndex;controller.CancelLearning();RefreshState();};
        actionPicker.SelectedIndexChanged+=(_,_)=>{if(loading||actionPicker.SelectedItem is not ActionChoice choice)return;Try(()=>{var bindings=controller.Config.Bindings.ToList();bindings[selectedIndex]=bindings[selectedIndex] with{Action=choice.Action};controller.Update(controller.Config with{Bindings=bindings});});};
        followApp.CheckedChanged+=(_,_)=>{if(!loading)Try(()=>controller.Update(controller.Config with{FollowActiveApp=followApp.Checked}));};
        Shown+=(_,_)=>{controller.ResumeIfConfigured();if(!controller.Config.DictationTested&&controller.AppPlugin?.App?.Supports(ActionKind.Dictate)==true)OpenQuickSetup();};
        controller.Changed+=RefreshState;FormClosing+=(_,e)=>{try{controller.Stop();}catch(Exception error){e.Cancel=true;ShowError(error);}};RefreshState();
    }
    private static Label MakeLabel(string text,float size,bool bold=false)=>new(){Text=text,AutoSize=true,ForeColor=bold?Palette.Ink:Palette.Muted,Font=new Font("Segoe UI",size,bold?FontStyle.Bold:FontStyle.Regular),BackColor=Color.Transparent,Margin=new Padding(3,4,3,4)};
    private static Label Block(string text){var value=MakeLabel(text,9);value.MaximumSize=new Size(470,0);value.Margin=new Padding(3,3,3,9);return value;}
    private static Control Section(string title){var value=MakeLabel(title,12,true);value.Margin=new Padding(3,18,3,8);return value;}
    private static FlowLayoutPanel Stack()=>new(){AutoSize=true,FlowDirection=FlowDirection.TopDown,WrapContents=false,BackColor=Color.White,Margin=Padding.Empty};
    private static Control Row(params Control[] children){var value=new FlowLayoutPanel{AutoSize=true,WrapContents=false,Margin=new Padding(0,4,0,6),BackColor=Color.White};value.Controls.AddRange(children);return value;}
    private static Panel Card()=>new(){Dock=DockStyle.Fill,BackColor=Color.White,Padding=new Padding(2)};
    private static Button Button(string text,Action action,bool primary=false){var button=new Button{Text=text,AutoSize=true,FlatStyle=FlatStyle.Flat,Padding=new Padding(10,6,10,6),Margin=new Padding(3,4,6,4),BackColor=primary?Palette.Accent:Color.White,ForeColor=primary?Color.White:Palette.Ink,Cursor=Cursors.Hand};button.FlatAppearance.BorderSize=primary?0:1;button.FlatAppearance.BorderColor=Color.FromArgb(224,228,237);button.Click+=(_,_)=>action();return button;}
    private sealed record ActionChoice(ActionKind Action,string Title);
    private static string ActionTitle(ActionKind action)=>action switch{ActionKind.Native=>"Keep original action",ActionKind.Dictate=>"Dictation",ActionKind.Focus=>"Show app",ActionKind.Send=>"Send (Return)",ActionKind.Backspace=>"Delete previous character",_=>"Escape"};
    private void LoadEditable(){loading=true;shortcut.Text=controller.Config.Shortcut;confirmed.Checked=controller.Config.ShortcutConfirmed;toggle.Checked=controller.Config.VoiceMode=="toggle";loading=false;}
    private void RefreshState()
    {
        if(selectedIndex>=controller.Config.Bindings.Count)selectedIndex=0;loading=true;var binding=controller.Config.Bindings[selectedIndex];var signature=string.Join('|',controller.Config.Bindings.Select(b=>b.ControlID+b.Name));
        if(signature!=bindingSignature){bindingPicker.DataSource=controller.Config.Bindings.Select(b=>b.Name).ToArray();bindingSignature=signature;}bindingPicker.SelectedIndex=selectedIndex;
        followApp.Checked=controller.Config.FollowActiveApp;routeLabel.Text=controller.Config.FollowActiveApp?(controller.Running?controller.RoutingLabel:"Connect remote to follow active app"):"Use only the selected app’s mappings";
        actionContext.Text=$"In {controller.AppPlugin?.Name??"this app"}, this button will…";
        selectedName.Text=binding.Name;linked.Text=binding.Usage==null?"Not linked yet":"Linked to your remote";linked.ForeColor=binding.Usage==null?Palette.Muted:Palette.Teal;
        var item=controller.Layout.Buttons.FirstOrDefault(b=>b.Id==binding.ControlID);hint.Text=item?.Hint??"Select a button on the remote, then link it to the matching physical button.";
        bool learning=controller.LearningIndex==selectedIndex;learn.Text=learning?"Waiting for your remote…":binding.Usage==null?"Learn this button":"Learn again";learn.Enabled=!learning;cancel.Visible=learning;
        learningHelp.Text=learning?$"Press only {binding.Name} on your physical remote. JustVibe Remote won’t run your saved action while learning.":"Learning identifies a button’s signal. It doesn’t trigger its assigned action.";
        var actionChoices=controller.AvailableActions.Select(action=>new ActionChoice(action,ActionTitle(action))).ToList();actionPicker.DisplayMember="Title";actionPicker.DataSource=actionChoices;actionPicker.SelectedItem=actionChoices.FirstOrDefault(choice=>choice.Action==binding.Action);actionHelp.Text=binding.Action==ActionKind.Native?"Keeps the remote’s normal behavior. Choose an action to personalize it.":binding.Usage==null?"Action selected. Learn this button to activate the mapping.":$"Saved for {controller.AppPlugin?.Name??"this app"}. Other app profiles keep their own actions.";
        microphoneStatus.Text=controller.MicrophoneSummary;
        voice.Visible=binding.Action==ActionKind.Dictate&&controller.AppPlugin?.App?.Supports(ActionKind.Dictate)==true;signal.Text=binding.Usage is Usage u?$"Button signal: {u}":"Button signal: not learned";
        target.Text=controller.Config.TargetAppPath.Length==0?$"App connection: use the running {controller.AppPlugin?.Name??"selected app"}.":$"App connection: {Path.GetFileName(controller.Config.TargetAppPath)}";
        canvas.UpdateRemote(controller.Layout,controller.Config.Bindings,binding.ControlID??$"button-{selectedIndex}",controller.ActiveUsages);
        int linkedCount=controller.Layout.Buttons.Count(item=>controller.Config.Bindings.Any(b=>b.ControlID==item.Id&&b.Usage!=null));progress.Text=$"{linkedCount} of {controller.Layout.Buttons.Count} buttons linked · {(controller.DevicePlugin?.Device?.Layout==null?"generic layout":"photo-based layout")}";
        badge.Text=controller.Running?controller.Connected>0?"Connected":"Looking for remote…":"Not connected";badge.ForeColor=controller.Connected>0?Palette.Teal:Palette.Muted;connect.Text=controller.Running?"Disconnect":"Connect remote";stopVoice.Visible=controller.VoiceActive;
        status.Text=controller.Status.StartsWith("Learned ")?$"{binding.Name} linked. Choose what it does above.":controller.Status;loading=false;
    }
    private void SelectControl(string id){int index=controller.Config.Bindings.FindIndex(b=>b.ControlID==id);if(index<0&&id.StartsWith("button-"))int.TryParse(id[7..],out index);if(index>=0&&index<controller.Config.Bindings.Count)selectedIndex=index;controller.CancelLearning();RefreshState();}
    private void TestMicrophone(){using var test=new MicrophoneTest(controller);test.ShowDialog(this);RefreshState();}
    private void OpenQuickSetup(){using var setup=new QuickSetup(controller);setup.ShowDialog(this);LoadEditable();RefreshState();}
    private void Connect(){if(controller.Running)Try(controller.Stop);else controller.Start();}
    private void Learn(){if(!controller.Running)controller.Start();if(controller.Running)controller.Learn(selectedIndex);}
    private void SaveVoice(){SaveVoiceSettings();}
    private bool SaveVoiceSettings(){try{controller.Update(controller.Config with{Shortcut=shortcut.Text,ShortcutConfirmed=confirmed.Checked,VoiceMode=toggle.Checked?"toggle":"hold"});return true;}catch(Exception error){ShowError(error);return false;}}
    private void TryVoice(){if(controller.VoiceActive){controller.StopVoice();return;}if(!controller.Running){controller.TestVoice();return;}if(SaveVoiceSettings())controller.TestVoice();}
    private void PopulatePlugins(){loading=true;devices.DataSource=controller.Catalog.Devices.ToList();devices.DisplayMember="Name";devices.SelectedItem=controller.Catalog.Devices.FirstOrDefault(p=>p.Id==controller.Config.DevicePluginID);apps.DataSource=controller.Catalog.Apps.ToList();apps.DisplayMember="Name";apps.SelectedItem=controller.Catalog.Apps.FirstOrDefault(p=>p.Id==controller.Config.AppPluginID);loading=false;}
    private void SelectPlugins(){if(loading||devices.SelectedItem is not PluginManifest d||apps.SelectedItem is not PluginManifest a)return;Try(()=>{controller.SelectPlugins(d.Id,a.Id);selectedIndex=0;LoadEditable();RefreshState();});}
    private void ChooseTarget(){using var dialog=new OpenFileDialog{Filter="Application (*.exe)|*.exe",Title="Choose the target application"};if(dialog.ShowDialog(this)==DialogResult.OK)Try(()=>controller.Update(controller.Config with{TargetAppPath=dialog.FileName}));}
    private void ManagePlugins(){var choice=MessageBox.Show(this,"Open the community plugin folder? Choose No to reload installed plugins instead. Reloading disconnects the remote.","Community plugins",MessageBoxButtons.YesNoCancel);Try(()=>{if(choice==DialogResult.Yes){Directory.CreateDirectory(controller.PluginDirectory);System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(controller.PluginDirectory){UseShellExecute=true});}else if(choice==DialogResult.No){controller.ReloadPlugins();PopulatePlugins();selectedIndex=0;RefreshState();}});}
    private void Try(Action action){try{action();}catch(Exception error){ShowError(error);}}
    private void ShowError(Exception error)=>MessageBox.Show(this,error.Message,"JustVibe Remote",MessageBoxButtons.OK,MessageBoxIcon.Information);
}
