using System.Text.Json;
using JustVibeRemote.Core;
namespace JustVibeRemote;

internal static class WorkspaceVerification
{
    public static void Run(string output)
    {
        Directory.CreateDirectory(output);
        string settings=Path.Combine(Path.GetTempPath(),"justvibe-ui-"+Guid.NewGuid().ToString("N"));
        int images=0;
        try
        {
            if(Application.HighDpiMode!=HighDpiMode.PerMonitorV2)throw new InvalidOperationException("Windows Forms is not using per-monitor DPI awareness.");
            using var window=new MainWindow(settings);
            window.VerifyPickerState();
            window.Show();Application.DoEvents();
            window.VerifyEditingWorkflows();
            VerifyReceiverDiscovery();
            images=window.VerifyWorkspace(output);
            images+=VerifyControlSurfaces(output);
            File.WriteAllText(Path.Combine(output,"verification.json"),JsonSerializer.Serialize(new{passed=true,images,editingWorkflows=true,hoverRepaint=true,typography="Segoe UI / native GDI text",dpiAwareness=Application.HighDpiMode.ToString(),os=Environment.OSVersion.ToString(),architecture=System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture.ToString(),dpi=window.DeviceDpi,deviceTests=false,audioCapture=false,notes="Profile isolation and persistence, button/action selection, stable picker data, voice field reload, repeated menu hover/leave repaint. Isolated temporary settings; no receiver started, no shortcuts sent, no audio capture. Test hardware and cross-app focus separately."},ConfigurationStore.Json));
            window.Close();
        }
        finally{if(Directory.Exists(settings))Directory.Delete(settings,true);}
    }
    public static void Capture(Form form,string path)
    {
        form.PerformLayout();Application.DoEvents();VerifyDisplayText(form);
        using var bitmap=new Bitmap(form.Width,form.Height);
        form.DrawToBitmap(bitmap,new Rectangle(Point.Empty,bitmap.Size));bitmap.Save(path,System.Drawing.Imaging.ImageFormat.Png);
    }
    private static void VerifyDisplayText(Control control)
    {
        string[] corrupted=["\u00e2\u20ac","\u00e2\u2020","\u00c2\u00b7","\u00c3\u00a2","\ufffd"];
        if(corrupted.Any(fragment=>control.Text.Contains(fragment,StringComparison.Ordinal)))throw new InvalidOperationException($"Corrupted UI text in {control.GetType().Name}: {control.Text}");
        foreach(Control child in control.Controls)VerifyDisplayText(child);
    }
    private sealed class KeyboardVerificationButton:PaintedButton
    {
        internal void VerifyActivation(Keys key)
        {
            if(!IsInputKey(key))throw new InvalidOperationException("Button activation key was treated as dialog navigation.");
            var down=new KeyEventArgs(key);OnKeyDown(down);OnKeyDown(new KeyEventArgs(key));
            if(down.SuppressKeyPress)throw new InvalidOperationException("Button suppressed the KeyUp event required for activation.");
            var character=new KeyPressEventArgs(key==Keys.Space?' ':'\r');OnKeyPress(character);
            if(!character.Handled)throw new InvalidOperationException("Button activation character was not consumed.");
            OnKeyUp(new KeyEventArgs(key));OnKeyUp(new KeyEventArgs(key));
        }
    }
    private static int VerifyControlSurfaces(string output)
    {
        using var form=new Form{Text="Control surfaces",ClientSize=new Size(820,470),Font=WorkspaceStyle.Text(),BackColor=Palette.Background,AutoScaleMode=AutoScaleMode.Dpi};
        var body=new EditorPanel{Dock=DockStyle.Fill,Padding=new Padding(28),BackColor=Palette.Background};form.Controls.Add(body);
        body.Controls.Add(WorkspaceStyle.Label("Controls & typography",20,true,true));body.Controls.Add(WorkspaceStyle.Label("Consistent text, spacing, borders and keyboard focus.",10));
        var disabled=WorkspaceStyle.Button("Unavailable",()=>{});disabled.Enabled=false;
        body.Controls.Add(WorkspaceStyle.Row(WorkspaceStyle.Button("Primary action",()=>{},true),WorkspaceStyle.Button("Secondary action",()=>{}),disabled));
        body.Controls.Add(WorkspaceStyle.Label("Search plugins",9,true));var search=new WorkspaceTextBox{PlaceholderText="Search by name or plugin ID",AccessibleName="Preview search"};body.Controls.Add(search);
        body.Controls.Add(WorkspaceStyle.Label("App profile",9,true));var picker=new WorkspacePicker{DropDownStyle=ComboBoxStyle.DropDownList};picker.Items.AddRange(new object[]{"ChatGPT","No specific app"});picker.SelectedIndex=0;body.Controls.Add(picker);
        var disabledInput=new WorkspaceTextBox{Text="No microphone selected",Enabled=false};body.Controls.Add(disabledInput);
        WorkspaceStyle.Apply(form);form.Show();Application.DoEvents();Capture(form,Path.Combine(output,"Controls.png"));
        using var keyboardButton=new KeyboardVerificationButton();int clicks=0;keyboardButton.Click+=(_,_)=>clicks++;
        keyboardButton.VerifyActivation(Keys.Enter);keyboardButton.VerifyActivation(Keys.Space);
        keyboardButton.Enabled=false;keyboardButton.VerifyActivation(Keys.Space);
        if(clicks!=2)throw new InvalidOperationException("Keyboard button activation must fire once and respect disabled state.");
        int changes=0;search.TextChanged+=(_,_)=>changes++;search.Text="chatgpt";if(changes!=1||search.Text!="chatgpt")throw new InvalidOperationException("Native search input no longer forwards text edits.");
        search.Focus();Application.DoEvents();if(!search.ContainsFocus)throw new InvalidOperationException("Input did not focus its native editor.");Capture(form,Path.Combine(output,"Controls-focused.png"));form.Close();return 2;
    }
    private static void VerifyReceiverDiscovery()
    {
        var catalog=new PluginCatalog(Path.Combine(AppContext.BaseDirectory,"plugins"),Path.Combine(Path.GetTempPath(),"justvibe-discovery-"+Guid.NewGuid().ToString("N")));
        var plugin=catalog.Devices.First();var profile=plugin.Device!.Profile;
        string prefix=$"\\\\?\\HID#VID_{profile.VendorId:X4}&PID_{profile.ProductId:X4}";
        string[] paths=[$"{prefix}&MI_00#receiver-a",$"{prefix}&MI_01#receiver-a",$"{prefix}&MI_02#receiver-a",@"\\?\HID#VID_FFFE&PID_FFFD&MI_00#unknown",@"\\?\HID#virtualdevice&Col01#unknown"];
        var grouped=AddRemoteFlow.GroupInterfaces(paths,catalog.Devices);
        var supported=grouped.Where(item=>item.PluginID!=null).ToArray();
        if(supported.Length!=1||supported[0].Paths.Length!=3||supported[0].PluginID!=plugin.Id||grouped.Count!=3)throw new InvalidOperationException("Receiver interfaces were not grouped without losing unknown devices.");
        if(AddRemoteFlow.GroupInterfaces([],catalog.Devices).Count!=0)throw new InvalidOperationException("Empty discovery invented a receiver.");
        var conflict=new PluginManifest{Id="test.conflicting-receiver",Name="Conflicting receiver",Kind="device",Device=plugin.Device};
        var ambiguous=AddRemoteFlow.GroupInterfaces(paths.Take(3),new[]{plugin,conflict});
        if(ambiguous.Count!=1||!ambiguous[0].Ambiguous||ambiguous[0].PluginID!=null)throw new InvalidOperationException("Overlapping device plugins became selectable.");
    }
}
internal sealed partial class MainWindow
{
    internal void VerifyEditingWorkflows()
    {
        var app=controller.Catalog.Apps.First(a=>a.App!.Supports(ActionKind.Dictate));
        var original=controller.Config;
        EditApp(app.Id);SelectControl(controller.Config.Bindings[0].ControlID!);
        actionPicker.SelectedItem=((List<ActionChoice>)actionPicker.DataSource!).First(c=>c.Action==ActionKind.Send);CommitSelectedAction();
        if(controller.Config.Bindings[0].Action!=ActionKind.Send)throw new InvalidOperationException("Action selection was not saved.");
        var source=actionPicker.DataSource;
        for(int i=0;i<10;i++)RefreshState();
        if(!ReferenceEquals(source,actionPicker.DataSource))throw new InvalidOperationException("Refreshing input replaced the action picker data.");
        var finalControl=controller.Config.Bindings[^1].ControlID!;mappingBoard.ChooseActionForVerification(finalControl,ActionKind.Escape);
        if(controller.Config.Bindings[^1].Action!=ActionKind.Escape||selectedIndex!=controller.Config.Bindings.Count-1)throw new InvalidOperationException("An inline card did not select and save its button action.");
        shortcut.Text="CTRL+SHIFT+D";confirmed.Checked=true;
        if(!SaveVoiceSettings())throw new InvalidOperationException("Could not save voice shortcut.");
        appProfiles.ChooseProfileForVerification(Configuration.NoSpecificAppID);
        if(controller.Config.AppPluginID!=Configuration.NoSpecificAppID)throw new InvalidOperationException("App profile strip did not switch the editor profile.");
        actionPicker.SelectedItem=((List<ActionChoice>)actionPicker.DataSource!).First(c=>c.Action==ActionKind.Native);CommitSelectedAction();
        EditApp(app.Id);
        if(controller.Config.Bindings[0].Action!=ActionKind.Send||shortcut.Text!="CTRL+SHIFT+D"||!confirmed.Checked)throw new InvalidOperationException("Profile switch lost the action or retained stale voice fields.");
        var saved=controller.Store.Load(new Configuration());
        if(saved.Shortcut!="CTRL+SHIFT+D"||saved.Bindings[0].Action!=ActionKind.Send)throw new InvalidOperationException("Editor changes did not persist to disk.");
        controller.Update(original);PopulatePlugins();LoadEditable();ShowPage(WorkspacePage.Remotes);
        if(RemoteController.DescribeRoute(true,original with{AppPluginID=Configuration.NoSpecificAppID},controller.Catalog)!="Active mapping: shared controls")throw new InvalidOperationException("Shared active-app routing failed.");
        using(var corners=new Bitmap(connect.Width,connect.Height))
        {
            connect.DrawToBitmap(corners,connect.ClientRectangle);
            if(corners.GetPixel(0,0).ToArgb()!=WorkspaceStyle.SurfaceColor(connect.Parent).ToArgb())throw new InvalidOperationException("Rounded button corners do not match their parent surface.");
        }
        foreach(var button in navigationButtons.Values)
        {
            button.PreviewHover(false);using var before=new Bitmap(button.Width,button.Height);button.DrawToBitmap(before,button.ClientRectangle);
            for(int i=0;i<8;i++){button.PreviewHover(true);button.Refresh();button.PreviewHover(false);button.Refresh();}
            using var after=new Bitmap(button.Width,button.Height);button.DrawToBitmap(after,button.ClientRectangle);
            for(int y=0;y<button.Height;y++)for(int x=0;x<button.Width;x++)if(before.GetPixel(x,y)!=after.GetPixel(x,y))throw new InvalidOperationException("Menu hover left painting artifacts: "+button.Text);
        }
        if(controller.Running||controller.MicrophoneTesting||controller.VoiceActive)throw new InvalidOperationException("Editor verification activated a device or audio.");
    }
    internal void VerifyPickerState()
    {
        if(bindingPicker.Items.Count!=controller.Config.Bindings.Count||bindingPicker.SelectedIndex!=selectedIndex)
            throw new InvalidOperationException("Button picker lost its items or selection while its page was hidden.");
        if(actionPicker.Items.Count!=controller.AvailableActions.Length||actionPicker.SelectedItem is not ActionChoice choice||choice.Action!=controller.Config.Bindings[selectedIndex].Action)
            throw new InvalidOperationException("Action picker does not match the selected button.");
        if(apps.Items.Count!=controller.Catalog.Apps.Count()+1||apps.SelectedItem is not PluginManifest app||app.Id!=controller.Config.AppPluginID)
            throw new InvalidOperationException("App picker lost its items or selected profile.");
        if(devices.SelectedItem is not PluginManifest device||device.Id!=controller.Config.DevicePluginID)
            throw new InvalidOperationException("Remote picker lost its selected receiver.");
    }
    internal int VerifyWorkspace(string output)
    {
        int images=0;
        using(var guide=new WindowsMicrophoneGuide())
        {
            guide.Show(this);Application.DoEvents();
            WorkspaceVerification.Capture(guide,Path.Combine(output,"Windows-microphone-setup.png"));images++;
            guide.ClientSize=new Size(620,520);Application.DoEvents();
            guide.VerifyPresentation();
            WorkspaceVerification.Capture(guide,Path.Combine(output,"Windows-microphone-setup-compact.png"));images++;
            guide.Close();
        }
        // Select a non-default button before visiting pages that detach its picker.
        int expectedBinding=Math.Min(1,controller.Config.Bindings.Count-1);
        bindingPicker.SelectedIndex=expectedBinding;
        foreach(var compact in new[]{false,true})
        {
            ClientSize=compact?new Size(1200,840):new Size(1400,940);
            foreach(var page in Enum.GetValues<WorkspacePage>())
            {
                ShowPage(page);PerformLayout();Application.DoEvents();
                VerifyPickerState();
                if(page==WorkspacePage.Buttons&&bindingPicker.Parent is ScrollableControl editor&&editor.HorizontalScroll.Visible)throw new InvalidOperationException("Button editor requires horizontal scrolling.");
                if(page==WorkspacePage.Buttons)mappingBoard.VerifyLayout();
                if(selectedIndex!=expectedBinding)throw new InvalidOperationException("Page navigation reset the selected button.");
                if(pageTitle.Text!=Title(page))throw new InvalidOperationException("Wrong page heading: "+page);
                if(pageTitle.Font.Name!="Segoe UI Semibold")throw new InvalidOperationException("Native heading font failed to load.");
                if(apps.Font.Name!="Segoe UI")throw new InvalidOperationException("Native control font failed to load.");
                void CheckTextRendering(Control control){if(control is Label label&&label.UseCompatibleTextRendering)throw new InvalidOperationException("A label is using a different text renderer.");foreach(Control child in control.Controls)CheckTextRendering(child);}
                CheckTextRendering(this);
                if(controller.Running||controller.VoiceActive||controller.MicrophoneTesting)throw new InvalidOperationException("Preview unexpectedly activated a device or microphone.");
                WorkspaceVerification.Capture(this,Path.Combine(output,page+(compact?"-compact":"")+".png"));images++;
            }
        }
        if(controller.MicrophoneIndex is int microphone)
        {
            var before=controller.Config;var bindings=before.Bindings.ToList();bindings[microphone]=bindings[microphone] with{Usage=new Usage(7,4)};controller.Update(before with{Bindings=bindings});
            selectedIndex=microphone;ShowPage(WorkspacePage.Buttons);mappingBoard.VerifyLayout();PerformLayout();Application.DoEvents();
            if(learn.Width<learn.GetPreferredSize(Size.Empty).Width||!learn.Parent!.ClientRectangle.Contains(learn.Bounds))throw new InvalidOperationException("Relink button is clipped after its text changes.");
            if(linked.Width<linked.GetPreferredSize(Size.Empty).Width)throw new InvalidOperationException("Linked status text is clipped.");
            string relinkText=learn.Text;learn.Text="Press remote button…";cancel.Visible=true;bindingPicker.Parent!.PerformLayout();
            if(!learn.Parent!.ClientRectangle.Contains(learn.Bounds)||!cancel.Parent!.ClientRectangle.Contains(cancel.Bounds))throw new InvalidOperationException("Learning or Cancel button is clipped.");
            learn.Text=relinkText;cancel.Visible=false;bindingPicker.Parent.PerformLayout();
            WorkspaceVerification.Capture(this,Path.Combine(output,"Buttons-dictation.png"));images++;controller.Update(before);
        }
        using(var voiceSettings=CreateVoiceSettingsDialog())
        {
            voiceSettings.Show(this);Application.DoEvents();
            if(!confirmed.Visible||!toggle.Visible||confirmed.Height<12||toggle.Height<12)throw new InvalidOperationException("Voice confirmation or activation controls are not visible.");
            shortcut.VerifyPresentation();
            if(shortcut.Width<200)throw new InvalidOperationException("Shortcut input collapsed in voice settings.");
            string previousShortcut=shortcut.Text;shortcut.PreviewDoubleClick();
            if(!shortcut.NativeReadOnly)throw new InvalidOperationException("Shortcut recorder did not enter capture mode.");
            foreach(var (keys,expected) in new[]{(Keys.Control|Keys.Shift|Keys.D,"CTRL+SHIFT+D"),(Keys.Control|Keys.A,"CTRL+A"),(Keys.Control|Keys.Space,"CTRL+SPACE"),(Keys.Alt|Keys.Enter,"ALT+ENTER"),(Keys.Shift|Keys.Back,"SHIFT+BACKSPACE"),(Keys.RMenu,"RALT")})
            {
                if(!shortcut.NativeReadOnly)shortcut.PreviewDoubleClick();
                if(!shortcut.PreviewCommand(keys)||shortcut.Text!=expected||shortcut.NativeReadOnly)throw new InvalidOperationException($"Shortcut command preprocessing failed: {keys}.");
                TargetOutput.ParseShortcut(shortcut.Text);
            }
            shortcut.PreviewDoubleClick();shortcut.PreviewCommand(Keys.Escape);
            if(shortcut.Text!="RALT"||shortcut.NativeReadOnly)throw new InvalidOperationException("Cancelling shortcut capture lost the previous value.");
            shortcut.PreviewDoubleClick();shortcut.PreviewCommand(Keys.Tab);
            if(shortcut.Text!="RALT"||shortcut.NativeReadOnly)throw new InvalidOperationException("Tab did not cancel shortcut capture.");
            shortcut.PreviewDoubleClick();confirmed.Focus();Application.DoEvents();
            if(shortcut.Text!="RALT"||shortcut.NativeReadOnly)throw new InvalidOperationException("Leaving shortcut capture did not restore its value.");
            shortcut.Text=previousShortcut;
            WorkspaceVerification.Capture(voiceSettings,Path.Combine(output,"App-voice-settings.png"));images++;voiceSettings.Close();
        }
        if(shortcut.IsDisposed||confirmed.IsDisposed||toggle.IsDisposed)throw new InvalidOperationException("Closing voice settings disposed reusable editor controls.");
        ShowPage(WorkspacePage.Remotes);
        using(var setup=new QuickSetup(controller))
        {
            setup.Show(this);Application.DoEvents();
            foreach(var stage in Enum.GetValues<RemoteSetupStage>()){setup.PreviewStage(stage);WorkspaceVerification.Capture(setup,Path.Combine(output,"Setup-"+stage+".png"));images++;}
            setup.Close();
        }
        using(var mic=new MicrophoneTest(controller)){mic.Show(this);WorkspaceVerification.Capture(mic,Path.Combine(output,"Microphone-test.png"));images++;mic.Close();}
        using(var voice=new VoiceTypingSetup(controller)){voice.Show(this);WorkspaceVerification.Capture(voice,Path.Combine(output,"Windows-voice-typing.png"));images++;voice.Close();}
        using(var add=new AddRemoteFlow(sessions.Catalog)){add.Show(this);Application.DoEvents();add.VerifyPresentation();WorkspaceVerification.Capture(add,Path.Combine(output,"Add-remote.png"));images++;add.Close();}
        if(controller.Running||controller.VoiceActive||controller.MicrophoneTesting)throw new InvalidOperationException("Preview left device work active.");
        return images;
    }
}
