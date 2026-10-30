using System.Drawing.Drawing2D;
using System.Text.RegularExpressions;
using JustVibeRemote.Core;

namespace JustVibeRemote;

internal sealed record DiscoveredRemote(string Key,string Name,string Identity,string? PluginID,string[] Paths,bool Ambiguous=false)
{
    public string Detail=>$"{Identity}  ·  {Paths.Length} HID interface{(Paths.Length==1?"":"s")}";
    public string Support=>PluginID!=null?"Ready to set up":Ambiguous?"Conflicting plugins":"Support needed";
    public override string ToString()=>$"{Name} — {Support}. {Detail}";
}

internal sealed class AddRemoteFlow:Form
{
    private readonly PluginCatalog catalog;
    private readonly RemoteDiscoveryList list=new(){Dock=DockStyle.Fill,Margin=Padding.Empty};
    private readonly Label summary=WorkspaceStyle.Label("",10),selection=WorkspaceStyle.Label("",9);
    private readonly CheckBox showOther=new(){AutoSize=true,Text="Show other input devices",Margin=new Padding(0,8,0,0)};
    private readonly TextBox details=new(){Dock=DockStyle.Fill,Multiline=true,ReadOnly=true,ScrollBars=ScrollBars.Both,WordWrap=false,BackColor=Color.White,BorderStyle=BorderStyle.FixedSingle,Visible=false,AccessibleName="Selected receiver interface details"};
    private readonly WorkspaceButton open,prompt,technical;
    private readonly TableLayoutPanel root;
    private List<DiscoveredRemote> discovered=[];
    public string? SelectedPluginID { get; private set; }
    private DiscoveredRemote? Selected=>list.SelectedItem as DiscoveredRemote;

    public AddRemoteFlow(PluginCatalog catalog)
    {
        this.catalog=catalog;
        Text="Add a remote";ClientSize=new Size(820,560);MinimumSize=new Size(740,560);StartPosition=FormStartPosition.CenterParent;Font=WorkspaceStyle.Text();AutoScaleMode=AutoScaleMode.Dpi;BackColor=Palette.Background;MinimizeBox=false;MaximizeBox=false;
        root=new TableLayoutPanel{Dock=DockStyle.Fill,Padding=new Padding(28),ColumnCount=1,RowCount=7};
        root.ColumnStyles.Add(new(SizeType.Percent,100));
        foreach(var height in new[]{92,64,0,104,0,62,52})root.RowStyles.Add(height==0&&root.RowStyles.Count==2?new(SizeType.Percent,100):new(SizeType.Absolute,height));
        Controls.Add(root);
        var header=WorkspaceStyle.Stack();header.Dock=DockStyle.Fill;header.Controls.Add(WorkspaceStyle.Label("Choose your remote",21,true,true));header.Controls.Add(WorkspaceStyle.Label("Connect its USB receiver or pair it in Windows, then choose it below.",10));root.Controls.Add(header,0,0);
        root.Controls.Add(WorkspaceStyle.Row(WorkspaceStyle.Button("Refresh",RefreshDevices),WorkspaceStyle.Button("Bluetooth settings",()=>WorkspaceStyle.Open("ms-settings:bluetooth"))),0,1);
        root.Controls.Add(list,0,2);
        var status=WorkspaceStyle.Stack();status.Dock=DockStyle.Fill;status.Controls.Add(summary);status.Controls.Add(selection);status.Controls.Add(showOther);root.Controls.Add(status,0,3);
        root.Controls.Add(details,0,4);
        technical=WorkspaceStyle.Button("Device details",ToggleDetails);
        prompt=WorkspaceStyle.Button("Create missing support…",CopySetupPrompt);
        root.Controls.Add(WorkspaceStyle.Row(technical,prompt),0,5);
        var footer=new FlowLayoutPanel{Dock=DockStyle.Fill,FlowDirection=FlowDirection.RightToLeft,WrapContents=false,Margin=Padding.Empty};
        open=WorkspaceStyle.Button("Set up remote",OpenSelected,true);open.Enabled=false;open.AccessibleName="Set up selected remote";
        footer.Controls.Add(open);footer.Controls.Add(WorkspaceStyle.Button("Cancel",()=>DialogResult=DialogResult.Cancel));root.Controls.Add(footer,0,6);
        list.SelectedIndexChanged+=(_,_)=>UpdateSelection();
        list.DoubleClick+=(_,_)=>OpenSelected();
        list.KeyDown+=(_,e)=>{if(e.KeyCode==Keys.Enter&&open.Enabled){e.Handled=true;OpenSelected();}};
        showOther.CheckedChanged+=(_,_)=>Populate();
        root.ClientSizeChanged+=(_,_)=>{int width=Math.Max(240,root.ClientSize.Width-root.Padding.Horizontal);foreach(var label in new[]{summary,selection})label.MaximumSize=new Size(width,0);};
        WorkspaceStyle.Apply(this);RefreshDevices();
    }
    internal void VerifyPresentation()
    {
        var supported=discovered.FirstOrDefault(item=>item.PluginID!=null);
        if(supported!=null&&(!open.Enabled||Selected?.Key!=supported.Key))throw new InvalidOperationException("Supported receiver was not selected for setup.");
        showOther.Checked=true;
        int unsupported=Enumerable.Range(0,list.Items.Count).FirstOrDefault(index=>((DiscoveredRemote)list.Items[index]).PluginID==null,-1);
        if(unsupported>=0){list.SelectedIndex=unsupported;if(open.Enabled||!prompt.Visible||!prompt.Enabled)throw new InvalidOperationException("An unsupported receiver can enter normal setup.");}
        if(list.Items.Count>0)
        {
            list.SelectedIndex=0;ToggleDetails();PerformLayout();
            if(!details.Visible||!details.Text.Contains(Selected!.Paths[0],StringComparison.Ordinal))throw new InvalidOperationException("Device details lost the selected evidence.");
            ToggleDetails();
        }
        showOther.Checked=false;Populate();PerformLayout();
        if(showOther.Visible&&showOther.Bottom>showOther.Parent!.ClientSize.Height)throw new InvalidOperationException("Other-input toggle is clipped.");
    }

    internal static List<DiscoveredRemote> GroupInterfaces(IEnumerable<string> paths,IEnumerable<PluginManifest> plugins)
    {
        var supported=plugins.ToArray();
        return paths.Distinct(StringComparer.OrdinalIgnoreCase).Select(path=>
        {
            var matches=supported.Where(d=>ReceiverDecoder.Matches(path,d.Device!.Profile)).OrderBy(d=>d.Id,StringComparer.Ordinal).ToArray();
            var hardware=Regex.Match(path,@"VID_([0-9A-F]{4})&PID_([0-9A-F]{4})",RegexOptions.IgnoreCase|RegexOptions.CultureInvariant);
            string identity=matches.Length>0?matches[0].Device!.Profile.HardwareId:hardware.Success?$"{hardware.Groups[1].Value.ToUpperInvariant()}:{hardware.Groups[2].Value.ToUpperInvariant()}":"Other HID inputs";
            string key=matches.Length>0?string.Join('|',matches.Select(m=>m.Id)):"other:"+identity;
            return new{Path=path,Matches=matches,Identity=identity,Key=key};
        }).GroupBy(item=>item.Key).Select(group=>
        {
            var first=group.First();
            return new DiscoveredRemote(group.Key,first.Matches.Length==1?first.Matches[0].Name:first.Matches.Length>1?"Multiple plugins match this receiver":first.Identity=="Other HID inputs"?"Other input interfaces":"Input device · "+first.Identity,first.Identity,first.Matches.Length==1?first.Matches[0].Id:null,group.Select(item=>item.Path).ToArray(),first.Matches.Length>1);
        }).OrderBy(item=>item.PluginID==null).ThenBy(item=>item.Name,StringComparer.CurrentCultureIgnoreCase).ToList();
    }

    private void RefreshDevices()
    {
        try{discovered=GroupInterfaces(NativeInput.Discover(),catalog.Devices);Populate();}
        catch(Exception error){discovered=[];Populate();summary.Text="Couldn’t refresh devices. Try again.";selection.Text=error.Message;}
    }
    private void Populate()
    {
        string? previous=Selected?.Key;list.BeginUpdate();list.Items.Clear();
        foreach(var item in discovered.Where(item=>item.PluginID!=null||item.Ambiguous||showOther.Checked))list.Items.Add(item);
        var candidates=list.Items.Cast<DiscoveredRemote>().ToArray();
        int selected=Array.FindIndex(candidates,item=>item.Key==previous);
        list.SelectedIndex=selected>=0?selected:Array.FindIndex(candidates,item=>item.PluginID!=null);list.EndUpdate();
        int supported=discovered.Count(item=>item.PluginID!=null),others=discovered.Count(item=>item.PluginID==null&&!item.Ambiguous);
        summary.Text=supported>0?$"{supported} supported receiver {(supported==1?"identity":"identities")} found":discovered.Any(item=>item.Ambiguous)?"Resolve the conflicting plugins to continue.":"No supported receiver found. Connect it and refresh.";
        showOther.Text=$"Show other input devices ({others})";showOther.Visible=others>0;
        list.EmptyMessage=showOther.Checked?"No input devices found.\nConnect your receiver and refresh.":"Your remote isn’t listed?\nConnect it and refresh, or show other input devices below.";
        UpdateSelection();ResizeForContent();list.Invalidate();
    }
    private void UpdateSelection()
    {
        var selected=Selected;open.Enabled=selected?.PluginID!=null;technical.Enabled=prompt.Enabled=selected!=null;
        prompt.Visible=selected?.PluginID==null;
        selection.Text=selected?.Ambiguous==true?"More than one plugin matches. Resolve the conflict before setup.":selected?.PluginID!=null?"Matching interfaces are grouped together. Choose Set up remote to continue.":selected!=null?"No installed plugin matches. Create a setup prompt to add support.":"Select a receiver to see setup options.";
        details.Text=selected==null?"":$"{selected.Name}\r\nReceiver identity: {selected.Identity}\r\n{selected.Paths.Length} matching HID interfaces (not a count of physical remotes).\r\nIdentity matching does not verify buttons or audio.\r\n\r\n"+string.Join("\r\n",selected.Paths);
    }
    private void ToggleDetails()
    {
        details.Visible=!details.Visible;root.RowStyles[4].Height=details.Visible?110*DeviceDpi/96f:0;technical.Text=details.Visible?"Hide device details":"Device details";ResizeForContent();
    }
    private void ResizeForContent()
    {
        int height=(560+(showOther.Checked?160:0)+(details.Visible?110:0))*DeviceDpi/96;
        ClientSize=new Size(ClientSize.Width,Math.Min(height,Math.Max(560,Screen.FromControl(this).WorkingArea.Height-100)));
    }
    private void OpenSelected(){if(Selected?.PluginID is not {} id)return;SelectedPluginID=id;DialogResult=DialogResult.OK;}
    private void CopySetupPrompt()
    {
        if(Selected is not {} selected)return;
        Clipboard.SetText("Help me identify my remote in JustVibe Remote on Windows. Ask for the model and a clear front photo. Use read-only receiver evidence; do not guess VID/PID, usages, or microphone transport. Check installed support before creating a plugin. Follow AGENTS.md and the PluginAuthoring guides. Observed interfaces:\n"+string.Join("\n",selected.Paths));
        selection.Text="Setup prompt copied. Paste it in your coding chat with a front photo of the remote.";
    }
}

internal sealed class RemoteDiscoveryList:ListBox
{
    private readonly Label empty=new(){Dock=DockStyle.Fill,TextAlign=ContentAlignment.MiddleCenter,ForeColor=Palette.Muted,BackColor=Palette.Background,Padding=new Padding(24),Visible=false};
    [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
    internal string EmptyMessage { get=>empty.Text;set{empty.Text=value;empty.Visible=Items.Count==0;} }
    public RemoteDiscoveryList(){DrawMode=DrawMode.OwnerDrawFixed;ItemHeight=76;IntegralHeight=false;BorderStyle=BorderStyle.None;BackColor=Palette.Background;AccessibleName="Detected receivers";HorizontalScrollbar=false;ResizeRedraw=true;Controls.Add(empty);}
    protected override void OnDrawItem(DrawItemEventArgs e)
    {
        if(e.Index<0||Items[e.Index] is not DiscoveredRemote item)return;
        var g=e.Graphics;g.SmoothingMode=SmoothingMode.AntiAlias;
        using(var background=new SolidBrush(BackColor))g.FillRectangle(background,e.Bounds);
        bool selected=(e.State&DrawItemState.Selected)!=0;
        var bounds=new RectangleF(e.Bounds.X+1,e.Bounds.Y+2,e.Bounds.Width-3,e.Bounds.Height-10);
        using var shape=Palette.Round(bounds,10);using var fill=new SolidBrush(selected?Color.FromArgb(235,239,255):Color.White);g.FillPath(fill,shape);
        using var pen=new Pen(selected?Palette.Accent:Palette.Border,selected?1.5f:1);g.DrawPath(pen,shape);
        float scale=DeviceDpi/96f;int left=e.Bounds.X+(int)(18*scale),badgeWidth=(int)(138*scale),width=Math.Max(40,e.Bounds.Width-badgeWidth-(int)(36*scale));
        WorkspaceStyle.DrawText(g,item.Name,WorkspaceStyle.Text(11,true),Rectangle.Round(new RectangleF(left,e.Bounds.Y+10*scale,width,24*scale)),Palette.Ink);
        WorkspaceStyle.DrawText(g,item.Detail,WorkspaceStyle.Text(9),Rectangle.Round(new RectangleF(left,e.Bounds.Y+35*scale,width,22*scale)),Palette.Muted);
        WorkspaceStyle.DrawText(g,item.Support,WorkspaceStyle.Text(9,true),Rectangle.Round(new RectangleF(e.Bounds.Right-badgeWidth,e.Bounds.Y+24*scale,badgeWidth-12*scale,24*scale)),item.PluginID!=null?Palette.Teal:Palette.Muted);
        if((e.State&DrawItemState.Focus)!=0&&Focused)e.DrawFocusRectangle();
    }
}
