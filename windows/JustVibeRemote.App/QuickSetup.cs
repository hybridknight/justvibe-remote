using JustVibeRemote.Core;
namespace JustVibeRemote;

internal sealed class QuickSetup:Form
{
    private readonly RemoteController controller;
    private RemoteSetupCheckpoint checkpoint;
    private readonly bool wasRunning;
    private readonly FlowLayoutPanel body=WorkspaceStyle.Stack(540),content=WorkspaceStyle.Stack(540);
    private readonly Label heading=WorkspaceStyle.Label("",21,true,true,540),lead=WorkspaceStyle.Label("",10.5f,false,false,540),feedback=WorkspaceStyle.Label("",9,false,false,540);
    private readonly Button back,primary;
    private readonly ShortcutRecorder shortcut=new(){Width=500};
    private readonly CheckBox wantsVoice=new(){Text="Set up voice input too (optional)",AutoSize=true},reconnect=new(){Text="Reconnect this remote when I open JustVibe",AutoSize=true},toggle=new(){Text="Press once to start voice, again to stop",AutoSize=true};
    private readonly ComboBox appPicker=new(){DropDownStyle=ComboBoxStyle.DropDownList,Width=500},bindingPicker=new(){DropDownStyle=ComboBoxStyle.DropDownList,Width=500};
    private readonly System.Windows.Forms.Timer timer=new(){Interval=400};
    private bool completed;
    public QuickSetup(RemoteController controller)
    {
        this.controller=controller;wasRunning=controller.Running;checkpoint=controller.Config.RemoteSetupCheckpoint??new();
        if(checkpoint.Stage==RemoteSetupStage.Done)checkpoint=new();
        Text="Set up "+(controller.DevicePlugin?.Name??"your remote");ClientSize=new Size(900,680);MinimumSize=new Size(800,620);StartPosition=FormStartPosition.CenterParent;Font=WorkspaceStyle.Text();AutoScaleMode=AutoScaleMode.Dpi;BackColor=Color.White;
        var root=new TableLayoutPanel{Dock=DockStyle.Fill,ColumnCount=2};root.ColumnStyles.Add(new(SizeType.Absolute,260));root.ColumnStyles.Add(new(SizeType.Percent,100));Controls.Add(root);
        var rail=new SidebarSurface{Dock=DockStyle.Fill,Padding=new Padding(28)};var milestones=WorkspaceStyle.Stack(200);milestones.Controls.Add(WorkspaceStyle.Label(controller.DevicePlugin?.Name??"Your remote",15,true,true,200));foreach(var text in new[]{"Welcome","Choose an app","Connect","Set up controls","Try it"})milestones.Controls.Add(WorkspaceStyle.Label(text,10,false,false,200));rail.Controls.Add(milestones);root.Controls.Add(rail,0,0);
        var main=new TableLayoutPanel{Dock=DockStyle.Fill,Padding=new Padding(28),RowCount=2,ColumnCount=1};main.RowStyles.Add(new(SizeType.Percent,100));main.RowStyles.Add(new(SizeType.Absolute,56));root.Controls.Add(main,1,0);
        body.Dock=DockStyle.Fill;body.AutoSize=false;body.AutoScroll=true;body.Controls.Add(heading);body.Controls.Add(lead);body.Controls.Add(content);body.Controls.Add(feedback);main.Controls.Add(body,0,0);
        back=WorkspaceStyle.Button("Back",Back);primary=WorkspaceStyle.Button("Continue",Next,true);main.Controls.Add(WorkspaceStyle.Row(back,WorkspaceStyle.Button("Continue later",Close),primary),0,1);
        shortcut.Text=controller.Config.Shortcut;toggle.Checked=controller.Config.VoiceMode=="toggle";reconnect.Checked=controller.Config.AutoConnect;wantsVoice.Checked=checkpoint.WantsVoice;
        timer.Tick+=(_,_)=>RefreshStatus();Shown+=(_,_)=>{controller.StopVoice();timer.Start();};
        FormClosing+=(_,e)=>{try{timer.Stop();controller.CancelLearning();controller.StopVoice();if(!completed)controller.SaveSetup(checkpoint);if(!completed&&!wasRunning)controller.Stop();}catch(Exception error){e.Cancel=true;MessageBox.Show(this,error.Message,Text);}};
        body.ClientSizeChanged+=(_,_)=>ResizeContent();
        Rebuild();WorkspaceStyle.Apply(this);
    }
    internal void PreviewStage(RemoteSetupStage stage){checkpoint=checkpoint with{Stage=stage};Rebuild();}
    private void Add(Control view){content.Controls.Add(view);}
    private void Note(string text)=>Add(WorkspaceStyle.Label(text,10,false,false,500));
    private void Rebuild()
    {
        // Persistent controls move between stages; dispose only stage-local controls.
        foreach(Control view in content.Controls.Cast<Control>().ToArray()){content.Controls.Remove(view);if(view!=shortcut&&view!=toggle&&view!=reconnect&&view!=appPicker&&view!=bindingPicker&&view!=wantsVoice)view.Dispose();}
        back.Enabled=checkpoint.Stage!=RemoteSetupStage.Welcome;lead.Text="";primary.Text=checkpoint.Stage==RemoteSetupStage.Welcome?"Get started":checkpoint.Stage==RemoteSetupStage.Practice?"The action works":checkpoint.Stage==RemoteSetupStage.Done?"Open remote":"Continue";
        switch(checkpoint.Stage)
        {
            case RemoteSetupStage.Welcome:heading.Text="Make this remote yours.";lead.Text="Choose an app, link a button, and try your first action.";Note("Voice is optional. Your receiver keeps its own settings, and you can continue setup later.");break;
            case RemoteSetupStage.App:
                heading.Text="Where will you use it?";lead.Text="Choose your first app. You can add more profiles afterward.";
                var choices=new[]{new PluginManifest{Id=Configuration.NoSpecificAppID,Name="No specific app"}}.Concat(controller.Catalog.Apps).ToList();appPicker.DataSource=choices;appPicker.DisplayMember="Name";appPicker.SelectedItem=choices.FirstOrDefault(a=>a.Id==controller.Config.AppPluginID);Add(appPicker);Add(wantsVoice);break;
            case RemoteSetupStage.Receiver:heading.Text="Connect your remote.";Note("Plug in its receiver or pair it in Windows Bluetooth settings, then connect it below.");Add(WorkspaceStyle.Button("Connect remote",()=>{controller.Start();RefreshStatus();},true));Add(WorkspaceStyle.Button("Bluetooth settings",()=>WorkspaceStyle.Open("ms-settings:bluetooth")));break;
            case RemoteSetupStage.Button:
                heading.Text="Make the buttons yours.";Note("Keep existing actions or link a control to personalize later in Buttons.");bindingPicker.DataSource=controller.Config.Bindings.Select(b=>b.Name).ToArray();Add(bindingPicker);Add(WorkspaceStyle.Button("Link selected button",()=>{if(!controller.Running)controller.Start();controller.Learn(Math.Max(0,bindingPicker.SelectedIndex));}));Add(WorkspaceStyle.Button("Cancel linking",controller.CancelLearning));break;
            case RemoteSetupStage.Microphone:
                heading.Text="Add voice to your remote.";Note("Link the microphone button, then check the selected audio input. Neither linking nor opening the test starts recording.");
                Add(WorkspaceStyle.Button("Link microphone button",()=>{if(controller.MicrophoneIndex is int index){var bindings=controller.Config.Bindings.ToList();bindings[index]=bindings[index] with{Action=ActionKind.Dictate};controller.Update(controller.Config with{Bindings=bindings});controller.Learn(index);}}));
                Add(WorkspaceStyle.Button("Test microphone…",()=>{using var test=new MicrophoneTest(controller);test.ShowDialog(this);}));Add(WorkspaceStyle.Button("Set up voice later",()=>{checkpoint=checkpoint with{WantsVoice=false,Stage=RemoteSetupStage.Practice};controller.SaveSetup(checkpoint);Rebuild();}));break;
            case RemoteSetupStage.Shortcut:
                heading.Text="Match your app’s shortcut.";Note("Confirm the hold-to-dictate shortcut in your app. Type it or double-click the field to record it.");Add(shortcut);Add(toggle);Add(WorkspaceStyle.Button("Open app",controller.ShowTargetApp));break;
            case RemoteSetupStage.Practice:
                heading.Text="Try your first action.";Note(checkpoint.WantsVoice?"Open your app, select its input field, and dictate a short phrase. Confirm only after you see the words.":"Open your app and try a linked button. Return after you see the expected action.");Add(WorkspaceStyle.Button("Open app",controller.ShowTargetApp));Add(reconnect);primary.Text=checkpoint.WantsVoice?"I see my text":"The button works";break;
            case RemoteSetupStage.Done:heading.Text="You’re ready.";Note("Your buttons and app profiles are saved for this receiver. Add more apps or customize buttons in the workspace.");break;
        }
        WorkspaceStyle.Apply(content);ResizeContent();body.ScrollControlIntoView(heading);RefreshStatus();
    }
    private void ResizeContent()
    {
        int width=Math.Max(200,body.ClientSize.Width-SystemInformation.VerticalScrollBarWidth);
        heading.MaximumSize=lead.MaximumSize=feedback.MaximumSize=new Size(width,0);
        content.MaximumSize=new Size(width,0);
        foreach(Control child in content.Controls){if(child is Label label)label.MaximumSize=new Size(width,0);else if(child is ComboBox or TextBox)child.Width=Math.Min(500,width);}
    }
    private void RefreshStatus(){feedback.Text=controller.Status;primary.Enabled=checkpoint.Stage switch{RemoteSetupStage.Receiver=>controller.Running&&controller.Connected>0,RemoteSetupStage.Microphone=>controller.MicrophoneIndex is int i&&controller.Config.Bindings[i].Usage!=null&&controller.Config.Bindings[i].Action==ActionKind.Dictate&&controller.LearningIndex==null,RemoteSetupStage.Practice=>controller.Running&&controller.Connected>0,_=>controller.LearningIndex==null};}
    private void Next()
    {
        try
        {
            var next=checkpoint.Stage+1;
            if(checkpoint.Stage==RemoteSetupStage.App)
            {
                if(appPicker.SelectedItem is PluginManifest app)controller.SelectPlugins(controller.Config.DevicePluginID,app.Id);
                checkpoint=checkpoint with{WantsVoice=wantsVoice.Checked&&controller.AppPlugin?.App?.Supports(ActionKind.Dictate)==true};
            }
            if(checkpoint.Stage==RemoteSetupStage.Button)next=checkpoint.WantsVoice?RemoteSetupStage.Microphone:RemoteSetupStage.Practice;
            if(checkpoint.Stage==RemoteSetupStage.Shortcut)controller.Update(controller.Config with{Shortcut=shortcut.Text,ShortcutConfirmed=true,VoiceMode=toggle.Checked?"toggle":"hold"});
            if(checkpoint.Stage==RemoteSetupStage.Practice){controller.Update(controller.Config with{AutoConnect=reconnect.Checked,DictationTested=checkpoint.WantsVoice});completed=true;controller.SaveSetup(checkpoint with{Stage=RemoteSetupStage.Done},true);}
            if(checkpoint.Stage==RemoteSetupStage.Done){Close();return;}
            controller.CancelLearning();checkpoint=checkpoint with{Stage=next};controller.SaveSetup(checkpoint,completed?true:null);Rebuild();
        }
        catch(Exception error){MessageBox.Show(this,error.Message,Text);}
    }
    private void Back(){if(checkpoint.Stage==RemoteSetupStage.Welcome)return;controller.CancelLearning();checkpoint=checkpoint with{Stage=checkpoint.Stage==RemoteSetupStage.Practice&&!checkpoint.WantsVoice?RemoteSetupStage.Button:checkpoint.Stage-1};controller.SaveSetup(checkpoint);Rebuild();}
    protected override void Dispose(bool disposing){if(disposing)timer.Dispose();base.Dispose(disposing);}
}
