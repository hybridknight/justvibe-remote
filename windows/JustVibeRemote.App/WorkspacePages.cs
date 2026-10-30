using JustVibeRemote.Core;
namespace JustVibeRemote;
internal sealed partial class MainWindow
{
    private WorkspacePage currentPage;
    private readonly Panel pageHost=new(){Dock=DockStyle.Fill,BackColor=Palette.Background};
    private readonly FlowLayoutPanel navigation=new(){Dock=DockStyle.Fill,FlowDirection=FlowDirection.TopDown,WrapContents=false,AutoScroll=true,Padding=new Padding(12,20,12,20),BackColor=Color.Transparent};
    private readonly Label pageTitle=WorkspaceStyle.Label("Remotes",23,true,true),pageSubtitle=WorkspaceStyle.Label("",10);
    private readonly Dictionary<WorkspacePage,NavigationButton> navigationButtons=[];
    private Control buttonsPage=null!;private Control? transientPage;private Action? refreshPage;
    private PictureBox? remoteArtwork;
    private static string Title(WorkspacePage page)=>page switch{WorkspacePage.Microphone=>"Microphone test",WorkspacePage.Settings=>"Remote settings",WorkspacePage.Help=>"Help & setup",WorkspacePage.ButtonTest=>"Button test",_=>page.ToString()};
    private void BuildWorkspace()
    {
        var shell=new TableLayoutPanel{Dock=DockStyle.Fill,ColumnCount=2,RowCount=1,Margin=Padding.Empty};shell.ColumnStyles.Add(new(SizeType.Absolute,240));shell.ColumnStyles.Add(new(SizeType.Percent,100));Controls.Add(shell);
        var sidebar=new SidebarSurface{Dock=DockStyle.Fill,Margin=Padding.Empty};sidebar.Controls.Add(navigation);shell.Controls.Add(sidebar,0,0);
        using(var stream=typeof(MainWindow).Assembly.GetManifestResourceStream("JustVibeRemote.Branding.ico")){if(stream!=null){using var icon=new Icon(stream);Icon=(Icon)icon.Clone();}}
        var content=new TableLayoutPanel{Dock=DockStyle.Fill,RowCount=3,ColumnCount=1,Padding=new Padding(28,24,28,16),Margin=Padding.Empty,BackColor=Palette.Background};content.RowStyles.Add(new(SizeType.Absolute,88));content.RowStyles.Add(new(SizeType.Percent,100));content.RowStyles.Add(new(SizeType.Absolute,44));shell.Controls.Add(content,1,0);
        var heading=new TableLayoutPanel{Dock=DockStyle.Fill,ColumnCount=2,Margin=Padding.Empty};heading.ColumnStyles.Add(new(SizeType.Percent,100));heading.ColumnStyles.Add(new(SizeType.AutoSize));
        var titles=Stack();titles.Controls.Add(pageTitle);titles.Controls.Add(pageSubtitle);heading.Controls.Add(titles,0,0);
        stopVoice=Button("Stop voice",sessions.StopVoices);stopVoice.Visible=false;heading.Controls.Add(stopVoice,1,0);content.Controls.Add(heading,0,0);
        content.Controls.Add(pageHost,0,1);status.Dock=DockStyle.Fill;status.AutoSize=false;status.MaximumSize=Size.Empty;content.Controls.Add(status,0,2);
        connect=Button("Connect remote",Connect,true);buttonsPage=BuildButtonsPage();BuildNavigation();
    }
    private void BuildNavigation()
    {
        foreach(Control item in navigation.Controls.Cast<Control>().ToArray())item.Dispose();navigation.Controls.Clear();navigationButtons.Clear();
        navigation.Controls.Add(WorkspaceStyle.Label("JustVibe",17,true,true,210));navigation.Controls.Add(WorkspaceStyle.Label("Remote",9,false,false,210));
        void Group(string title){var label=WorkspaceStyle.Label(title,8.5f,true,false,210);label.Margin=new Padding(12,24,0,12);navigation.Controls.Add(label);}
        void Item(WorkspacePage page,string? title=null){var button=new NavigationButton(title??Title(page),(int)page,()=>ShowPage(page));navigationButtons[page]=button;navigation.Controls.Add(button);}
        Group("Library");Item(WorkspacePage.Remotes);Item(WorkspacePage.Plugins);
        if(sessions.Initial!=null){Group(controller.DevicePlugin?.Name??"Selected remote");Item(WorkspacePage.Overview);Item(WorkspacePage.Apps);Item(WorkspacePage.Buttons);Item(WorkspacePage.Microphone,"Microphone");Item(WorkspacePage.Settings,"Settings");}
        Group("Resources");Item(WorkspacePage.Help);
    }
    private void SelectRemote(string id)
    {
        if(!sessions.Controllers.TryGetValue(id,out var next))return;
        controller.SetButtonTest(false);controller.CancelLearning();controller=next;selectedIndex=0;bindingSignature="";PopulatePlugins();LoadEditable();BuildNavigation();ShowPage(WorkspacePage.Overview);RefreshState();
    }
    private void ShowPage(WorkspacePage page)
    {
        if(sessions.Initial==null&&page is not (WorkspacePage.Remotes or WorkspacePage.Plugins or WorkspacePage.Help))page=WorkspacePage.Remotes;
        controller.SetButtonTest(false);controller.CancelLearning();currentPage=page;refreshPage=null;
        pageHost.Controls.Clear();remoteArtwork?.Image?.Dispose();remoteArtwork=null;transientPage?.Dispose();transientPage=null;
        pageTitle.Text=Title(page);pageSubtitle.Text=page is WorkspacePage.Remotes?"Start with a remote, then configure its apps and buttons.":page is WorkspacePage.Plugins?"Installed support for remotes and apps.":page is WorkspacePage.Help?"Guided setup and troubleshooting.":controller.DevicePlugin?.Name??"Select a remote";
        Control view=page switch{WorkspacePage.Remotes=>BuildRemotesPage(),WorkspacePage.Overview=>BuildOverviewPage(),WorkspacePage.Apps=>BuildAppsPage(),WorkspacePage.Buttons=>buttonsPage,WorkspacePage.ButtonTest=>BuildButtonTestPage(),WorkspacePage.Microphone=>BuildMicrophonePage(),WorkspacePage.Settings=>BuildSettingsPage(),WorkspacePage.Plugins=>BuildPluginsPage(),_=>BuildHelpPage()};
        if(view!=buttonsPage)transientPage=view;view.Dock=DockStyle.Fill;pageHost.Controls.Add(view);WorkspaceStyle.Apply(view);
        foreach(var (key,button) in navigationButtons){button.Selected=key==(page==WorkspacePage.ButtonTest?WorkspacePage.Buttons:page);button.Invalidate();}
        controller.SetButtonTest(page==WorkspacePage.ButtonTest&&ContainsFocus);RefreshState();
    }
    private FlowLayoutPanel Page(params Control[] controls)
    {
        var page=new FlowLayoutPanel{Dock=DockStyle.Fill,FlowDirection=FlowDirection.TopDown,WrapContents=false,AutoScroll=true,BackColor=Palette.Background,Margin=Padding.Empty};page.Controls.AddRange(controls);return page;
    }
    private Panel ContentCard(string title,string detail,params Control[] controls)
    {
        var list=new List<Control>{WorkspaceStyle.Label(title,12.5f,true,true),WorkspaceStyle.Label(detail)};list.AddRange(controls);return WorkspaceStyle.Card(list.ToArray());
    }
    private Control BuildRemotesPage()
    {
        var page=Page();var states=new List<(Label Label,RemoteController Controller)>();
        if(!sessions.Catalog.Devices.Any())page.Controls.Add(ContentCard("Add your first remote","Install support for your receiver, then set up its buttons.",Button("Add a remote…",AddRemote,true)));
        foreach(var device in sessions.Catalog.Devices)
        {
            var session=sessions.Controllers[device.Id];var state=MakeLabel("",10);states.Add((state,session));
            var details=WorkspaceStyle.Stack(500);details.Controls.Add(WorkspaceStyle.Label(device.Name,17,true,true,500));details.Controls.Add(WorkspaceStyle.Label("Independent app profiles, buttons, and microphone choice.",10,false,false,500));details.Controls.Add(state);
            details.Controls.Add(Row(Button(session.Config.RemoteSetupCompleted?"Open remote →":"Set up remote →",()=>{SelectRemote(device.Id);if(!session.Config.RemoteSetupCompleted)OpenQuickSetup();},true),Button("Connect / disconnect",()=>Try(()=>{if(session.Running)session.Stop();else session.Start();}))));
            page.Controls.Add(WorkspaceStyle.Card(Row(ArtworkView(session),details)));
        }
        page.Controls.Add(ContentCard("Add another remote","Pair it in Windows or plug in its USB receiver first.",Button("Add a remote…",AddRemote)));
        refreshPage=()=>{foreach(var item in states)item.Label.Text=item.Controller.Running?item.Controller.Connected>0?"Connected":"Waiting for receiver":"Not connected";};return page;
    }
    private Control BuildOverviewPage()
    {
        var health=MakeLabel("",10);refreshPage=()=>health.Text=$"Connection: {(controller.Connected>0?"Connected":"Not connected")}\nApp profile: {controller.AppPlugin?.Name??"No specific app"}\n{controller.MicrophoneSummary}";
        return Page(ContentCard(controller.Config.RemoteSetupCompleted?"Make every button yours":"Your next step","Set up this remote, then choose its apps and button actions.",Row(ArtworkView(controller),Button(controller.Config.RemoteSetupCompleted?"Review settings":"Continue setup",OpenQuickSetup,true))),ContentCard("This remote","",health),ContentCard("Configure this remote","Changes apply to this receiver.",Row(Button("Apps",()=>ShowPage(WorkspacePage.Apps)),Button("Buttons",()=>ShowPage(WorkspacePage.Buttons)),Button("Microphone",()=>ShowPage(WorkspacePage.Microphone)))));
    }
    private Control BuildButtonsPage()
    {
        var root=new TableLayoutPanel{Dock=DockStyle.Fill,ColumnCount=1,RowCount=2,Margin=Padding.Empty};root.RowStyles.Add(new(SizeType.Absolute,64));root.RowStyles.Add(new(SizeType.Percent,100));
        root.Controls.Add(Row(MakeLabel("Edit app",9,true),apps,Button("Add app…",AddApplication),Button("Button test…",()=>ShowPage(WorkspacePage.ButtonTest))),0,0);
        var columns=new TableLayoutPanel{Dock=DockStyle.Fill,ColumnCount=2,Margin=Padding.Empty};columns.ColumnStyles.Add(new(SizeType.Percent,40));columns.ColumnStyles.Add(new(SizeType.Percent,60));root.Controls.Add(columns,0,1);
        var remote=Card();remote.Margin=new Padding(0,0,12,0);remote.Controls.Add(canvas);progress.Dock=DockStyle.Bottom;progress.Height=36;progress.AutoSize=false;remote.Controls.Add(progress);columns.Controls.Add(remote,0,0);canvas.Selected+=SelectControl;
        var inspector=Card();var form=Stack();form.Dock=DockStyle.Fill;form.AutoSize=false;form.AutoScroll=true;form.Padding=new Padding(24);form.BackColor=Color.White;inspector.Controls.Add(form);columns.Controls.Add(inspector,1,0);
        form.Controls.Add(MakeLabel("REMOTE BUTTON",9,true));form.Controls.Add(bindingPicker);form.Controls.Add(selectedName);form.Controls.Add(linked);form.Controls.Add(hint);
        learn=Button("Link this button",Learn,true);cancel=Button("Cancel",()=>controller.CancelLearning());cancel.Visible=false;form.Controls.Add(Row(learn,cancel));form.Controls.Add(learningHelp);form.Controls.Add(actionContext);form.Controls.Add(actionPicker);launchAppButton=Button("Choose apps…",ChooseLaunchApp);form.Controls.Add(launchAppButton);form.Controls.Add(actionHelp);form.Controls.Add(Button("Apply to all apps",()=>Try(()=>controller.ApplyActionToAllApps(selectedIndex))));
        voice.Controls.Add(Section("Voice setup"));voice.Controls.Add(Button("Test microphone…",TestMicrophone));voice.Controls.Add(microphoneStatus);voice.Controls.Add(Block("Match the shortcut configured in the selected app. Double-click the shortcut field to record it, or type it."));voice.Controls.Add(shortcut);voice.Controls.Add(Button("Save voice settings",SaveVoice));voice.Controls.Add(confirmed);voice.Controls.Add(toggle);voice.Controls.Add(Row(Button("Try dictation",TryVoice),Button("Locate app…",ChooseTarget)));form.Controls.Add(voice);
        form.Controls.Add(target);form.Controls.Add(Button("Advanced & app connection",()=>advanced.Visible=!advanced.Visible));advanced.Controls.Add(signal);advanced.Controls.Add(Block("Windows keeps native remote actions. Mapped actions run alongside them. Native typing is not suppressed."));advanced.Visible=false;form.Controls.Add(advanced);
        form.SizeChanged+=(_,_)=>{var width=Math.Max(120,form.ClientSize.Width-64);bindingPicker.Width=actionPicker.Width=width;shortcut.Width=Math.Min(320,width);foreach(var label in new[]{hint,learningHelp,actionHelp,target,signal,microphoneStatus})label.MaximumSize=new Size(width,0);voice.Width=width;voice.MaximumSize=new Size(width,0);};WorkspaceStyle.Apply(root);return root;
    }
    private Control BuildAppsPage()
    {
        var page=Page(ContentCard("Supported apps","Use a configured app profile, or keep ordinary remote actions with No specific app.",Button("Add app…",AddApplication,true)));
        page.AllowDrop=true;page.DragEnter+=(_,e)=>{if(e.Data?.GetDataPresent(DataFormats.FileDrop)==true)e.Effect=DragDropEffects.Copy;};page.DragDrop+=(_,e)=>{if(e.Data?.GetData(DataFormats.FileDrop) is string[] files&&files.Length==1)AddApplicationPath(files[0]);};
        page.Controls.Add(ContentCard("No specific app","Keep native remote actions and optional Windows voice typing.",Button("Configure →",()=>{Try(()=>controller.SelectPlugins(controller.Config.DevicePluginID,Configuration.NoSpecificAppID));PopulatePlugins();ShowPage(WorkspacePage.Buttons);} )));
        foreach(var app in sessions.Catalog.Apps)page.Controls.Add(ContentCard(app.Name,app.App!.Supports(ActionKind.Dictate)?"Buttons and app dictation":"Button actions",Row(Button("Configure →",()=>{Try(()=>controller.SelectPlugins(controller.Config.DevicePluginID,app.Id));PopulatePlugins();LoadEditable();ShowPage(WorkspacePage.Buttons);},true),Button("Locate app…",()=>{Try(()=>controller.SelectPlugins(controller.Config.DevicePluginID,app.Id));PopulatePlugins();ChooseTarget();}))));
        page.Controls.Add(ContentCard("Dictation in any app","Windows voice typing uses Win+H in the focused input. Windows controls its microphone session.",Button("Set up Windows voice typing…",SetupVoiceTyping)));
        return page;
    }
    private Control BuildMicrophonePage()=>Page(ContentCard("Hear your remote","Choose an input, record a bounded five-second preview, then play it back. Recording starts only when you select Start test.",MakeLabel(controller.MicrophoneSummary,10),Button("Open microphone test…",TestMicrophone,true)));
    private Control BuildSettingsPage()
    {
        var connectionButton=Button(controller.Running?"Disconnect":"Connect remote",Connect,true);
        refreshPage=()=>connectionButton.Text=controller.Running?"Disconnect":"Connect remote";
        var reconnect=new CheckBox{Text="Reconnect this remote when I open JustVibe Remote",AutoSize=true,Checked=controller.Config.AutoConnect};reconnect.CheckedChanged+=(_,_)=>Try(()=>controller.Update(controller.Config with{AutoConnect=reconnect.Checked}));
        var routing=new CheckBox{Text="Follow active app",AutoSize=true,Checked=controller.Config.FollowActiveApp};routing.CheckedChanged+=(_,_)=>Try(()=>controller.Update(controller.Config with{FollowActiveApp=routing.Checked}));
        remoteArtwork=new PictureBox{Size=new Size(150,180),SizeMode=PictureBoxSizeMode.Zoom};LoadRemoteArtwork();
        return Page(ContentCard("Connection","Connection and reconnect settings for this receiver.",Row(connectionButton,Button("Connection check…",ConnectionCheck),Button("Run setup guide…",OpenQuickSetup)),reconnect),ContentCard("App switching","Use configured profiles without changing the profile displayed in the editor.",routing),ContentCard("Dictation in any app","Use Windows voice typing when your app has no configured dictation shortcut.",Button("Configure Windows voice typing…",SetupVoiceTyping)),ContentCard("Remote artwork","Use a local photo for this receiver. Button layouts remain defined by its plugin.",remoteArtwork,Row(Button("Choose photo…",ChooseArtwork),Button("Reset photo",()=>Try(()=>{controller.Update(controller.Config with{ArtworkPath=""});LoadRemoteArtwork();})))),ContentCard("Cursor settings","Windows' standard mouse controls affect all mice. Per-receiver speed and acceleration are not exposed by this adapter.",Button("Open Windows mouse settings",()=>WorkspaceStyle.Open("ms-settings:mousetouchpad"))));
    }
    private Control BuildPluginsPage()
    {
        var list=Page();var search=new TextBox{Width=700,PlaceholderText="Search installed plugins",Margin=new Padding(0,0,0,24)};
        var page=new Panel{Dock=DockStyle.Fill};search.Dock=DockStyle.Top;list.Dock=DockStyle.Fill;page.Controls.Add(list);page.Controls.Add(search);
        void Populate()
        {
            foreach(Control item in list.Controls.Cast<Control>().ToArray())item.Dispose();list.Controls.Clear();
            foreach(var plugin in sessions.Catalog.Plugins.Where(p=>(p.Name+" "+p.Id+" "+p.Kind).Contains(search.Text,StringComparison.OrdinalIgnoreCase)))list.Controls.Add(ContentCard(plugin.Name,$"{plugin.Kind} · Version {plugin.Version} · {plugin.Author}\n{plugin.Id}",Button(plugin.Kind=="device"?"Open remote →":"Choose app →",()=>{if(plugin.Kind=="device")SelectRemote(plugin.Id);else{Try(()=>controller.SelectPlugins(controller.Config.DevicePluginID,plugin.Id));PopulatePlugins();ShowPage(WorkspacePage.Buttons);}})));
            if(sessions.Catalog.Diagnostics.Count>0)list.Controls.Add(ContentCard("Plugin diagnostics",string.Join("\n",sessions.Catalog.Diagnostics)));
            list.Controls.Add(ContentCard("Install community plugins","Place each plugin folder in your user plugin directory. Reloading explicitly disconnects receivers.",Row(Button("Open plugin folder",()=>{Directory.CreateDirectory(sessions.PluginDirectory);WorkspaceStyle.Open(sessions.PluginDirectory);}),Button("Reload plugins",()=>Try(()=>{var id=controller.Config.DevicePluginID;sessions.Reload();controller=sessions.Controllers.GetValueOrDefault(id)??sessions.Initial??controller;PopulatePlugins();BuildNavigation();ShowPage(WorkspacePage.Plugins);})))));
        }
        search.TextChanged+=(_,_)=>Populate();Populate();return page;
    }
    private Control BuildHelpPage()=>Page(ContentCard("A clear path from setup to your first action","1. Open a remote from Remotes.\n2. Choose an app inside that remote.\n3. Link its buttons and assign actions.\n4. Configure microphone and voice if needed.",Button("Choose a remote →",()=>ShowPage(WorkspacePage.Remotes),true)),ContentCard("Something isn’t working?","No buttons: check the receiver connection.\nNo app action: check the selected profile, focus, and button link.\nWindows cannot send shortcuts into higher-privilege apps: run both apps at the same permission level.\nNo voice: match the shortcut and app microphone selection.",Row(Button("Connection check",ConnectionCheck),Button("Microphone test",TestMicrophone),Button("Open setup guides",()=>WorkspaceStyle.Open(Path.Combine(AppContext.BaseDirectory,"PluginAuthoring","guides"))))));
    private Control BuildButtonTestPage()
    {
        var test=new RemoteCanvas{Height=520,Width=700};test.Selected+=SelectControl;
        var state=MakeLabel("",10);var page=Page(ContentCard("Button test","Mapped actions are paused in this window. Native Windows input still reaches the focused application. Keep focus here while testing.",state,Row(Button("Connect to test",Connect),Button("Relink selected button",Learn),Button("Back to buttons",()=>ShowPage(WorkspacePage.Buttons)))),test);
        refreshPage=()=>{state.Text=controller.Connected>0?"Connected · press a remote button":"Connect this receiver to test";test.UpdateRemote(controller.Layout,controller.Config.Bindings,controller.Config.Bindings.ElementAtOrDefault(selectedIndex)?.ControlID,controller.ActiveUsages);};return page;
    }
    private void AddRemote(){using var flow=new AddRemoteFlow(sessions.Catalog);if(flow.ShowDialog(this)==DialogResult.OK&&flow.SelectedPluginID is {} id){SelectRemote(id);OpenQuickSetup();}}
    private void AddApplication(){using var dialog=new OpenFileDialog{Filter="Windows application (*.exe)|*.exe",Title="Add an app"};if(dialog.ShowDialog(this)==DialogResult.OK)AddApplicationPath(dialog.FileName);}
    private void AddApplicationPath(string path)=>Try(()=>{
        path=Path.GetFullPath(path);if(!File.Exists(path)||!path.EndsWith(".exe",StringComparison.OrdinalIgnoreCase))throw new InvalidDataException("Choose a Windows application (.exe).");
        string? voiceShortcut=null;
        var known=sessions.Catalog.Apps.Any(p=>p.App?.Targets.GetValueOrDefault("windows")?.Names.Contains(Path.GetFileNameWithoutExtension(path),StringComparer.OrdinalIgnoreCase)==true);
        if(!known)
        {
            using var dialog=new Form{Text="Add app profile",ClientSize=new Size(600,330),StartPosition=FormStartPosition.CenterParent,Font=WorkspaceStyle.Text(),BackColor=Color.White,AutoScaleMode=AutoScaleMode.Dpi};
            var stack=WorkspaceStyle.Stack(540);stack.Dock=DockStyle.Fill;stack.Padding=new Padding(28);stack.AutoSize=false;stack.AutoScroll=true;dialog.Controls.Add(stack);
            stack.Controls.Add(WorkspaceStyle.Label("Add "+Path.GetFileNameWithoutExtension(path),16,true,true,530));
            stack.Controls.Add(WorkspaceStyle.Label("Buttons work without voice. Add dictation only if this app has a verified hold-to-dictate shortcut.",10,false,false,530));
            var voice=new CheckBox{Text="This app supports hold-to-dictate",AutoSize=true};var keys=new ShortcutRecorder{Width=500,PlaceholderText="Example: CTRL+SHIFT+M"};stack.Controls.Add(voice);stack.Controls.Add(keys);
            stack.Controls.Add(Row(Button("Cancel",()=>dialog.DialogResult=DialogResult.Cancel),Button("Add profile",()=>{try{if(voice.Checked){PluginManifest.ValidateShortcut(keys.Text,"windows");voiceShortcut=keys.Text;}dialog.DialogResult=DialogResult.OK;}catch(Exception error){MessageBox.Show(dialog,error.Message,dialog.Text);}},true)));
            WorkspaceStyle.Apply(dialog);if(dialog.ShowDialog(this)!=DialogResult.OK)return;
        }
        var plugin=sessions.AddApp(path,voiceShortcut);
        bool configured=controller.Config.AppPluginID==plugin.Id||controller.Config.AppMappings.ContainsKey(AppRouting.Key(controller.Config.DevicePluginID,plugin.Id))||controller.Config.BindingSets.ContainsKey(AppRouting.Key(controller.Config.DevicePluginID,plugin.Id));
        controller.SelectPlugins(controller.Config.DevicePluginID,plugin.Id);
        controller.Update(controller.Config with{TargetAppPath=Path.GetFullPath(path),Bindings=!configured&&plugin.Id.StartsWith("local.justviberemote.app.",StringComparison.Ordinal)?controller.Config.Bindings.Select(b=>b with{Action=ActionKind.Native}).ToList():controller.Config.Bindings});PopulatePlugins();LoadEditable();ShowPage(WorkspacePage.Buttons);
    });
    private void SetupVoiceTyping(){using var setup=new VoiceTypingSetup(controller);setup.ShowDialog(this);RefreshState();}
    private void ChooseLaunchApp()
    {
        var session=controller;int index=selectedIndex;
        var choices=session.Catalog.Apps.OrderBy(p=>p.Name,StringComparer.CurrentCultureIgnoreCase).ToArray();
        if(choices.Length==0){MessageBox.Show(this,"Add an app in Apps before assigning Open app.","Open app");RefreshState();return;}
        using var dialog=new Form{Text="Open apps",ClientSize=new Size(620,590),StartPosition=FormStartPosition.CenterParent,Font=WorkspaceStyle.Text(),BackColor=Color.White,AutoScaleMode=AutoScaleMode.Dpi};
        var stack=WorkspaceStyle.Stack(564);stack.Dock=DockStyle.Fill;stack.AutoSize=false;stack.AutoScroll=true;stack.Padding=new Padding(28);dialog.Controls.Add(stack);
        stack.Controls.Add(WorkspaceStyle.Label("Open apps",18,true,true,550));stack.Controls.Add(WorkspaceStyle.Label($"Select apps for {session.Config.Bindings[index].Name}. Each press opens the next checked app, from top to bottom, then starts again. A running app is brought to the front.",10,false,false,550));
        var binding=session.Config.Bindings[index];
        var saved=binding.LaunchApps??[new LaunchApp(binding.LaunchAppID??session.Config.AppPluginID,binding.LaunchAppPath)];
        var ordered=saved.Select(t=>choices.FirstOrDefault(p=>p.Id==t.Id)).OfType<PluginManifest>().Concat(choices.Where(p=>!saved.Any(t=>t.Id==p.Id))).ToArray();
        var picker=new CheckedListBox{Width=550,Height=220,CheckOnClick=true,DisplayMember="Name",AccessibleName="Apps to open in order"};
        foreach(var app in ordered)picker.Items.Add(app,saved.Any(t=>t.Id==app.Id));
        var paths=saved.ToDictionary(t=>t.Id,t=>t.Path??"");
        var location=WorkspaceStyle.Label("",9,false,false,550);
        string CurrentPath(PluginManifest app)
        {
            string path=paths.GetValueOrDefault(app.Id)??"";
            if(path.Length==0)path=app.Id==session.Config.AppPluginID?session.Config.TargetAppPath:session.Config.AppMappings.GetValueOrDefault(AppRouting.Key(session.Config.DevicePluginID,app.Id))?.TargetAppPath??"";
            return path.Length>0?path:TargetOutput.RunningPath(app);
        }
        bool Locate(PluginManifest app)
        {
            using var file=new OpenFileDialog{Filter="Windows application (*.exe)|*.exe",Title="Locate "+app.Name,CheckFileExists=true};
            if(file.ShowDialog(dialog)!=DialogResult.OK)return false;
            paths[app.Id]=Path.GetFullPath(file.FileName);location.Text=paths[app.Id];return true;
        }
        picker.SelectedIndexChanged+=(_,_)=>{if(picker.SelectedItem is PluginManifest app){var path=CurrentPath(app);location.Text=path.Length>0?path:"Locate this app’s .exe so it can open when closed.";}};
        stack.Controls.Add(picker);stack.Controls.Add(location);stack.Controls.Add(Button("Locate selected app…",()=>{if(picker.SelectedItem is PluginManifest app)Locate(app);}));
        stack.Controls.Add(Row(Button("Cancel",()=>dialog.DialogResult=DialogResult.Cancel),Button("Save Action",()=>{
            var selected=picker.CheckedItems.Cast<PluginManifest>().ToArray();
            if(selected.Length is <1 or >64){MessageBox.Show(dialog,"Select between 1 and 64 apps.","Open apps");return;}
            var targets=new List<LaunchApp>();
            foreach(var app in selected)
            {
                string path=CurrentPath(app);
                if(!File.Exists(path)||!path.EndsWith(".exe",StringComparison.OrdinalIgnoreCase)){if(!Locate(app))return;path=paths[app.Id];}
                targets.Add(new(app.Id,path));
            }
            try{var bindings=session.Config.Bindings.ToList();bindings[index]=bindings[index] with{Action=ActionKind.Focus,LaunchAppID=targets[0].Id,LaunchAppPath=targets[0].Path,LaunchApps=targets.Count>1?targets:null};session.Update(session.Config with{Bindings=bindings});dialog.DialogResult=DialogResult.OK;}
            catch(Exception error){MessageBox.Show(dialog,error.Message,"Open apps");}
        },true)));WorkspaceStyle.Apply(dialog);
        dialog.ShowDialog(this);RefreshState();
    }

    private void ConnectionCheck()
    {
        var count=NativeInput.Discover().Count(path=>ReceiverDecoder.Matches(path,controller.Config.Profile));
        MessageBox.Show(this,$"Receiver: {controller.Config.Profile.HardwareId}\nMatching interfaces: {count}\nListener: {(controller.Running?"Running":"Stopped")}\n{controller.Status}\n\nWindows native actions remain enabled. App shortcuts require the same privilege level as JustVibe.\n\nPlugin diagnostics:\n{string.Join("\n",sessions.Catalog.Diagnostics)}","Connection check",MessageBoxButtons.OK,MessageBoxIcon.Information);
    }
    private void ChooseArtwork()
    {
        using var dialog=new OpenFileDialog{Filter="Remote photo (*.png;*.jpg;*.jpeg)|*.png;*.jpg;*.jpeg"};if(dialog.ShowDialog(this)!=DialogResult.OK)return;
        Try(()=>{var info=new FileInfo(dialog.FileName);if(info.Length>16*1024*1024)throw new InvalidDataException("Choose an image smaller than 16 MB.");using(var image=Image.FromFile(dialog.FileName)){if((long)image.Width*image.Height>32_000_000)throw new InvalidDataException("Choose an image under 32 megapixels.");}
            var directory=Path.Combine(Path.GetDirectoryName(controller.Store.Path)!,"artwork");Directory.CreateDirectory(directory);var path=Path.Combine(directory,Guid.NewGuid()+Path.GetExtension(dialog.FileName).ToLowerInvariant());File.Copy(dialog.FileName,path);controller.Update(controller.Config with{ArtworkPath=path});LoadRemoteArtwork();});
    }
    private Control ArtworkView(RemoteController session)
    {
        if(File.Exists(session.Config.ArtworkPath))
        {
            try
            {
                using var image=Image.FromFile(session.Config.ArtworkPath);
                var photo=new PictureBox{Image=new Bitmap(image),Size=new Size(130,190),SizeMode=PictureBoxSizeMode.Zoom,AccessibleName=session.DevicePlugin?.Name??"Remote photo",Margin=new Padding(0,0,24,12)};
                photo.Disposed+=(_,_)=>photo.Image?.Dispose();return photo;
            }
            catch(Exception error) when(error is IOException or ArgumentException or OutOfMemoryException){ }
        }
        var preview=new RemoteCanvas{Size=new Size(130,190),Enabled=false,Margin=new Padding(0,0,24,12)};
        preview.UpdateRemote(session.Layout,session.Config.Bindings,null,[]);return preview;
    }
    private void LoadRemoteArtwork()
    {
        if(remoteArtwork==null)return;
        remoteArtwork.Image?.Dispose();remoteArtwork.Image=null;
        if(!File.Exists(controller.Config.ArtworkPath))return;
        try{using var image=Image.FromFile(controller.Config.ArtworkPath);remoteArtwork.Image=new Bitmap(image);}
        catch(Exception error) when(error is IOException or ArgumentException or OutOfMemoryException){remoteArtwork.AccessibleDescription="Photo unavailable: "+error.Message;}
    }
}
