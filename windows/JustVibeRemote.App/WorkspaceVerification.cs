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
            using var window=new MainWindow(settings);
            window.Show();Application.DoEvents();
            images=window.VerifyWorkspace(output);
            File.WriteAllText(Path.Combine(output,"verification.json"),JsonSerializer.Serialize(new{passed=true,images,os=Environment.OSVersion.ToString(),architecture=System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture.ToString(),dpi=window.DeviceDpi,deviceTests=false,audioCapture=false,notes="Isolated temporary settings; no receiver started, no shortcuts sent, no audio capture. Test hardware and cross-app focus separately."},ConfigurationStore.Json));
            window.Close();
        }
        finally{if(Directory.Exists(settings))Directory.Delete(settings,true);}
    }
    public static void Capture(Form form,string path)
    {
        form.PerformLayout();Application.DoEvents();
        using var bitmap=new Bitmap(form.ClientSize.Width,form.ClientSize.Height);
        form.DrawToBitmap(bitmap,new Rectangle(Point.Empty,bitmap.Size));bitmap.Save(path,System.Drawing.Imaging.ImageFormat.Png);
    }
}
internal sealed partial class MainWindow
{
    internal int VerifyWorkspace(string output)
    {
        int images=0;
        foreach(var compact in new[]{false,true})
        {
            ClientSize=compact?new Size(1200,840):new Size(1380,940);
            foreach(var page in Enum.GetValues<WorkspacePage>())
            {
                ShowPage(page);PerformLayout();Application.DoEvents();
                if(pageTitle.Text!=Title(page))throw new InvalidOperationException("Wrong page heading: "+page);
                if(!pageTitle.Font.FontFamily.Name.Contains("Manrope"))throw new InvalidOperationException("Bundled heading font failed to load.");
                if(!apps.Font.FontFamily.Name.Contains("Inter"))throw new InvalidOperationException("Bundled control font failed to load.");
                if(controller.Running||controller.VoiceActive||controller.MicrophoneTesting)throw new InvalidOperationException("Preview unexpectedly activated a device or microphone.");
                WorkspaceVerification.Capture(this,Path.Combine(output,page+(compact?"-compact":"")+".png"));images++;
            }
        }
        ShowPage(WorkspacePage.Remotes);
        using(var setup=new QuickSetup(controller))
        {
            setup.Show(this);Application.DoEvents();
            foreach(var stage in Enum.GetValues<RemoteSetupStage>()){setup.PreviewStage(stage);WorkspaceVerification.Capture(setup,Path.Combine(output,"Setup-"+stage+".png"));images++;}
            setup.Close();
        }
        using(var mic=new MicrophoneTest(controller)){mic.Show(this);WorkspaceVerification.Capture(mic,Path.Combine(output,"Microphone-test.png"));images++;mic.Close();}
        using(var voice=new VoiceTypingSetup(controller)){voice.Show(this);WorkspaceVerification.Capture(voice,Path.Combine(output,"Windows-voice-typing.png"));images++;voice.Close();}
        using(var add=new AddRemoteFlow(sessions.Catalog)){add.Show(this);WorkspaceVerification.Capture(add,Path.Combine(output,"Add-remote.png"));images++;add.Close();}
        if(controller.Running||controller.VoiceActive||controller.MicrophoneTesting)throw new InvalidOperationException("Preview left device work active.");
        return images;
    }
}
