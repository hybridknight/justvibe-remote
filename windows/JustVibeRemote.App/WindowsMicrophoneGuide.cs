namespace JustVibeRemote;

internal sealed class WindowsMicrophoneGuide:Form
{
    private readonly Image screenshot;

    public WindowsMicrophoneGuide()
    {
        Text="Windows microphone setup";
        ClientSize=new Size(940,820);
        MinimumSize=new Size(620,520);
        StartPosition=FormStartPosition.CenterParent;
        AutoScaleMode=AutoScaleMode.Dpi;
        Font=WorkspaceStyle.Text();
        BackColor=Palette.Background;

        using var stream=typeof(WindowsMicrophoneGuide).Assembly.GetManifestResourceStream("JustVibeRemote.Help.WindowsSoundInput.png")
            ??throw new InvalidOperationException("Windows microphone setup screenshot is missing.");
        using var source=Image.FromStream(stream);
        screenshot=new Bitmap(source);

        var layout=new TableLayoutPanel{Dock=DockStyle.Fill,ColumnCount=1,RowCount=2};
        layout.ColumnStyles.Add(new(SizeType.Percent,100));
        layout.RowStyles.Add(new(SizeType.Percent,100));
        layout.RowStyles.Add(new(SizeType.Absolute,70));
        Controls.Add(layout);
        var content=new Panel{Dock=DockStyle.Fill,AutoScroll=true,Padding=new Padding(24)};
        layout.Controls.Add(content,0,0);
        var heading=WorkspaceStyle.Label("Windows microphone setup",20,true,true);
        var steps=WorkspaceStyle.Label("1. Open Windows Settings → System → Sound. Under Input, select your remote microphone.\n2. Open More sound settings → Recording. Right-click that microphone and choose Set as Default Device and Set as Default Communication Device, if offered.\n3. In JustVibe’s microphone test, save the same input. Check for ‘All Windows input defaults match this mic’, then close the test.\n4. In your target app, choose this microphone or System Default if available. Confirm the app shortcut in JustVibe’s voice settings.");
        var caption=WorkspaceStyle.Label("Example: Microphone / Mic Device is selected below. Your remote may have a different name. The screenshot shows the regular default; set the communications default separately in More sound settings.");
        var picture=new PictureBox{Image=screenshot,SizeMode=PictureBoxSizeMode.Zoom,AccessibleName="Windows Sound settings: remote microphone selected as default input; More sound settings at the bottom",Margin=new Padding(0,12,0,12)};
        content.Controls.AddRange([heading,steps,caption,picture]);
        void ResizeContent()
        {
            int width=Math.Max(200,content.ClientSize.Width-content.Padding.Horizontal-SystemInformation.VerticalScrollBarWidth);
            content.AutoScrollPosition=Point.Empty;
            int top=content.Padding.Top;
            foreach(var label in new[]{heading,steps,caption})
            {
                label.AutoSize=false;
                label.MaximumSize=new Size(width,0);
                int height=TextRenderer.MeasureText(label.Text,label.Font,new Size(width,int.MaxValue),TextFormatFlags.WordBreak|TextFormatFlags.NoPrefix).Height;
                label.Size=new Size(width,height+2);
                label.Location=new Point(content.Padding.Left,top);
                top+=label.Height+8;
            }
            picture.Size=new Size(width,(int)Math.Round(width*(double)screenshot.Height/screenshot.Width));
            picture.Location=new Point(content.Padding.Left,top+4);
            content.AutoScrollMinSize=new Size(0,picture.Bottom+content.Padding.Bottom);
            content.PerformLayout();
        }
        content.ClientSizeChanged+=(_,_)=>ResizeContent();
        var footer=new FlowLayoutPanel{Dock=DockStyle.Fill,FlowDirection=FlowDirection.RightToLeft,WrapContents=false,Padding=new Padding(16),BackColor=Color.White};
        footer.Controls.Add(WorkspaceStyle.Button("Close",Close));
        footer.Controls.Add(WorkspaceStyle.Button("Open Windows Sound settings",()=>WorkspaceStyle.Open("ms-settings:sound"),true));
        layout.Controls.Add(footer,0,1);
        WorkspaceStyle.Apply(this);
        ResizeContent();
    }

    protected override void Dispose(bool disposing)
    {
        if(disposing)screenshot.Dispose();
        base.Dispose(disposing);
    }

    internal void VerifyPresentation()
    {
        var content=Controls[0].Controls.OfType<Panel>().First();
        if(content.HorizontalScroll.Visible)throw new InvalidOperationException($"Microphone help requires horizontal scrolling: {content.ClientSize}, {content.DisplayRectangle}, {content.AutoScrollMinSize}; "+string.Join("; ",content.Controls.Cast<Control>().Select(c=>$"{c.GetType().Name}: {c.Bounds}")));
    }
}

internal sealed partial class MainWindow
{
    private void ShowWindowsMicrophoneGuide()
    {
        using var guide=new WindowsMicrophoneGuide();
        guide.ShowDialog(this);
    }
}
