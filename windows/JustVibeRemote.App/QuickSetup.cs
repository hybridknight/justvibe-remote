using JustVibeRemote.Core;

namespace JustVibeRemote;
internal sealed class QuickSetup : Form
{
    private readonly RemoteController controller;
    private readonly bool wasRunning;
    private readonly Label stage=new(){AutoSize=true,ForeColor=Palette.Accent,Font=new Font("Segoe UI",9,FontStyle.Bold)},heading=new(){AutoSize=true,ForeColor=Palette.Ink,Font=new Font("Segoe UI",21,FontStyle.Bold)};
    private readonly Label description=Block(12),detail=Block(10),status=Block(9);
    private readonly TextBox shortcut=new(){Width=310};
    private readonly CheckBox reconnect=new(){Text="Reconnect automatically when I open JustVibe Remote",AutoSize=true};
    private readonly Button primary=new(){AutoSize=true,BackColor=Palette.Accent,ForeColor=Color.White,FlatStyle=FlatStyle.Flat,Padding=new Padding(10,7,10,7)},secondary=new(){AutoSize=true},relearn=new(){Text="Button not responding? Learn it again",AutoSize=true};
    private readonly Button microphoneTest=new(){Text="Test microphone…",AutoSize=true};
    private readonly System.Windows.Forms.Timer timer=new(){Interval=400};
    private SetupStep? previous;private bool attempted,allowConnect,completed,closed;
    public QuickSetup(RemoteController controller)
    {
        this.controller=controller;wasRunning=controller.Running;
        Text="Quick setup";ClientSize=new Size(620,520);FormBorderStyle=FormBorderStyle.FixedDialog;MaximizeBox=false;MinimizeBox=false;StartPosition=FormStartPosition.CenterParent;BackColor=Color.White;Font=new Font("Segoe UI",10);AutoScaleMode=AutoScaleMode.Dpi;
        var stack=new FlowLayoutPanel{Dock=DockStyle.Fill,FlowDirection=FlowDirection.TopDown,WrapContents=false,AutoScroll=true,Padding=new Padding(28),BackColor=Color.White};Controls.Add(stack);
        stack.Controls.Add(stage);stack.Controls.Add(heading);stack.Controls.Add(description);stack.Controls.Add(detail);
        shortcut.Text=controller.Config.Shortcut;stack.Controls.Add(shortcut);reconnect.Checked=controller.Config.AutoConnect||!controller.Config.DictationTested;stack.Controls.Add(reconnect);stack.Controls.Add(relearn);stack.Controls.Add(microphoneTest);stack.Controls.Add(status);
        var actions=new FlowLayoutPanel{AutoSize=true,WrapContents=false};var cancel=new Button{Text="Not now",AutoSize=true};actions.Controls.Add(primary);actions.Controls.Add(secondary);actions.Controls.Add(cancel);stack.Controls.Add(actions);
        primary.FlatAppearance.BorderSize=0;primary.Click+=(_,_)=>Advance();secondary.Click+=(_,_)=>{if(Step==SetupStep.Microphone)LearnAgain();else if(Step is SetupStep.Shortcut or SetupStep.Test)controller.ShowTargetApp();else RefreshStep();};
        microphoneTest.Click+=(_,_)=>{using var test=new MicrophoneTest(controller);test.ShowDialog(this);};
        relearn.Click+=(_,_)=>LearnAgain();cancel.Click+=(_,_)=>Close();
        timer.Tick+=(_,_)=>RefreshStep();Shown+=(_,_)=>{controller.StopVoice();timer.Start();};
        FormClosing+=(_,_)=>{if(closed)return;closed=true;timer.Stop();controller.CancelLearning();controller.StopVoice();if(!completed&&!wasRunning){try{controller.Stop();}catch(Exception error){MessageBox.Show(this,error.Message,"Quick setup");}}};
        RefreshStep();
    }
    private SetupStep Step=>controller.Connected>0&&controller.LearningIndex!=null&&controller.LearningIndex==controller.MicrophoneIndex?SetupStep.Microphone:controller.SetupProgress.Step;
    private static Label Block(float size)=>new(){AutoSize=true,MaximumSize=new Size(545,0),ForeColor=Palette.Muted,Font=new Font("Segoe UI",size),Margin=new Padding(3,8,3,10)};
    private void RefreshStep()
    {
        if(closed)return;
        if(allowConnect&&!controller.Running&&!attempted){attempted=true;controller.Start();}
        var step=Step;
        if(step!=previous){previous=step;if(step==SetupStep.Microphone&&controller.MicrophoneIndex is int index&&controller.LearningIndex!=index)LearnAgain();}
        var app=controller.AppPlugin?.Name??"your app";
        microphoneTest.Visible=step is SetupStep.Test or SetupStep.Ready;shortcut.Visible=step==SetupStep.Shortcut;reconnect.Visible=step is SetupStep.Test or SetupStep.Ready;relearn.Visible=step==SetupStep.Test;primary.Enabled=true;secondary.Visible=false;status.Text=controller.Status;
        switch(step)
        {
            case SetupStep.Receiver:
                stage.Text="1 OF 3 · CONNECT";heading.Text="Connect your remote";
                description.Text=$"Plug in the USB receiver or pair {controller.Config.Profile.Name} in Windows Bluetooth settings. We’ll detect it and move on automatically.";
                detail.Text=controller.Running?"Waiting for the remote. Check its USB connection or Bluetooth pairing if it does not appear.":"Your plugins are already selected. Click Connect remote to continue.";
                primary.Text=controller.Running?"Try reconnecting":"Connect remote";break;
            case SetupStep.Microphone:
                stage.Text="2 OF 3 · PRESS ONE BUTTON";heading.Text="Press the microphone button";
                description.Text="Press only the microphone button on your physical remote once. We’ll remember it for you.";
                detail.Text="If nothing happens, check batteries and the receiver, then try again. Learning does not run your saved action.";
                primary.Text="Listening for your button…";primary.Enabled=false;secondary.Visible=true;secondary.Text="Try again";
                if(controller.MicrophoneIndex==null){primary.Text="Open button editor";primary.Enabled=true;detail.Text="This plugin has no microphone control. Assign Dictation to a button in the editor, then run setup again.";}break;
            case SetupStep.Shortcut:
                stage.Text="3 OF 3 · MATCH YOUR APP";heading.Text="Confirm your dictation shortcut";
                description.Text=$"Enter the same hold-to-dictate shortcut shown in {app}’s settings. You only need to do this once.";
                detail.Text="Examples: RALT or CTRL+SHIFT+D. The suggestion is not an automatic reading of your app settings.";
                primary.Text="Use this shortcut";secondary.Visible=true;secondary.Text=$"Open {app}";break;
            case SetupStep.Test:
                stage.Text="3 OF 3 · TRY IT";heading.Text="Say a short phrase";
                description.Text=$"Open {app}. Press the remote’s microphone button, speak, then {(controller.Config.VoiceMode=="toggle"?"press it again":"release it")} to finish.";
                detail.Text=$"In {app}, select the same mic tested in Microphone test, or System Default. Return here when you see the words appear.";
                primary.Text="I see the text — finish";secondary.Visible=true;secondary.Text=$"Open {app}";break;
            case SetupStep.Ready:
                stage.Text="ALL SET";heading.Text="Your remote is ready";description.Text="Your remote and app settings are saved. Keep JustVibe Remote open while using the remote.";detail.Text="Reconnect can be automatic the next time you launch the app.";primary.Text="Done";break;
        }
    }
    private void LearnAgain()
    {
        if(controller.MicrophoneIndex is not int index)return;
        try
        {
            if(controller.Config.Bindings[index].Action!=ActionKind.Dictate){var bindings=controller.Config.Bindings.ToList();bindings[index]=bindings[index] with{Action=ActionKind.Dictate};controller.Update(controller.Config with{Bindings=bindings});}
            controller.Learn(index);
        }catch(Exception error){MessageBox.Show(this,error.Message,"Quick setup");}
    }
    private void Advance()
    {
        allowConnect=true;
        try
        {
            switch(Step)
            {
                case SetupStep.Receiver:if(controller.Running)controller.Stop();attempted=true;controller.Start();break;
                case SetupStep.Microphone:if(controller.MicrophoneIndex==null)Close();break;
                case SetupStep.Shortcut:controller.Update(controller.Config with{Shortcut=shortcut.Text,ShortcutConfirmed=true});break;
                case SetupStep.Test:case SetupStep.Ready:
                    controller.Update(controller.Config with{DictationTested=controller.SetupProgress.NeedsDictation||controller.Config.DictationTested,AutoConnect=reconnect.Checked});completed=true;Close();return;
            }
        }catch(Exception error){MessageBox.Show(this,error.Message,"Quick setup");}
        RefreshStep();
    }
    protected override void Dispose(bool disposing){if(disposing)timer.Dispose();base.Dispose(disposing);}
}
