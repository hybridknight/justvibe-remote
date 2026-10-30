using System.Drawing.Drawing2D;
using JustVibeRemote.Core;
using RemoteBinding=JustVibeRemote.Core.Binding;

namespace JustVibeRemote;

// Mirrors the macOS mapping board. Geometry and signals still come exclusively
// from the selected device plugin and the user's learned bindings.
internal sealed class RemoteMappingBoard:Panel
{
    private readonly RemoteCanvas canvas;
    private readonly List<MappingCard> cards=[];
    private RemoteLayout? model;
    private string? selectedID;
    public event Action<string>? Selected,Learn;
    public event Action<string,ActionKind>? Assigned;
    public event Action? CancelLearning;
    internal int CardCount=>cards.Count;
    internal void ChooseActionForVerification(string id,ActionKind action)=>cards.First(card=>card.Control.Id==id).ChooseActionForVerification(action);
    public RemoteMappingBoard(RemoteCanvas canvas)
    {
        this.canvas=canvas;DoubleBuffered=true;BackColor=Palette.Background;
        canvas.Dock=DockStyle.None;canvas.BackColor=BackColor;Controls.Add(canvas);
        canvas.ConnectionPainter=g=>{var state=g.Save();g.TranslateTransform(-canvas.Left,-canvas.Top);DrawConnections(g);g.Restore(state);};
    }
    public void UpdateRemote(RemoteLayout layout,List<RemoteBinding> bindings,string? selection,ActionKind[] actions,int? learningIndex,HashSet<Usage> active,string shortcut,IEnumerable<PluginManifest> apps,string currentAppID)
    {
        if(model==null||!model.Buttons.SequenceEqual(layout.Buttons)||model.Width!=layout.Width||model.Height!=layout.Height)
        {
            foreach(var card in cards)card.Dispose();cards.Clear();model=layout;
            foreach(var control in layout.Buttons.OrderBy(control=>control.Bounds.Y).ThenBy(control=>control.Bounds.X))
            {
                var card=new MappingCard(control);card.Choose+=()=>Selected?.Invoke(control.Id);card.Assign+=action=>Assigned?.Invoke(control.Id,action);
                card.Link+=cancel=>{if(cancel)CancelLearning?.Invoke();else Learn?.Invoke(control.Id);};cards.Add(card);Controls.Add(card);
            }
        }
        selectedID=selection;string? learningID=learningIndex is int index?bindings[index].ControlID??$"button-{index}":null;
        foreach(var card in cards)
        {
            var binding=bindings.FirstOrDefault(binding=>binding.ControlID==card.Control.Id||card.Control.Id.StartsWith("button-",StringComparison.Ordinal)&&binding.Name==card.Control.Label);
            var target=apps.FirstOrDefault(app=>app.Id==(binding?.LaunchAppID??currentAppID));
            card.UpdateBinding(binding,actions,selection==card.Control.Id,learningID==card.Control.Id,learningID!=null,active,shortcut,target?.Name);
        }
        PerformLayout();Invalidate();canvas.Invalidate();
    }
    protected override void OnLayout(LayoutEventArgs e)
    {
        base.OnLayout(e);if(model==null)return;
        var left=new List<MappingCard>();var right=new List<MappingCard>();
        foreach(var card in cards)
        {
            double center=card.Control.Bounds.X+card.Control.Bounds.Width/2;
            if(Math.Abs(center-model.Width/2)<1){if(left.Count<=right.Count)left.Add(card);else right.Add(card);}
            else if(center<model.Width/2)left.Add(card);else right.Add(card);
        }
        float scale=DeviceDpi/96f;
        int rows=Math.Max(1,Math.Max(left.Count,right.Count)),pitch=Math.Min((int)(60*scale),Math.Max(36,(Height-(int)(24*scale))/rows));
        int centerWidth=Math.Min((int)(220*scale),Math.Max((int)(140*scale),(int)(Width*.23f)));
        int cardWidth=Math.Max(80,(Width-centerWidth-(int)(40*scale))/2);
        canvas.Bounds=new Rectangle((Width-centerWidth)/2,(int)(12*scale),centerWidth,Math.Max(1,Height-(int)(24*scale)));
        foreach(var (side,isLeft) in new[]{(left,true),(right,false)})for(int index=0;index<side.Count;index++)side[index].Bounds=new Rectangle(isLeft?0:Width-cardWidth,(int)(12*scale)+index*pitch,cardWidth,pitch-(int)(6*scale));
    }
    protected override void OnPaint(PaintEventArgs e){base.OnPaint(e);DrawConnections(e.Graphics);}
    private void DrawConnections(Graphics graphics)
    {
        graphics.SmoothingMode=SmoothingMode.AntiAlias;
        foreach(var card in cards.OrderBy(card=>card.Control.Id==selectedID))
        {
            var point=canvas.CenterOf(card.Control.Id);if(point==null)continue;
            var start=new PointF(canvas.Left+point.Value.X,canvas.Top+point.Value.Y);
            bool left=card.Left<canvas.Left,chosen=card.Control.Id==selectedID;
            var end=new PointF(left?card.Right:card.Left,card.Top+card.Height/2f);float bend=(end.X-start.X)*.55f;
            using var pen=new Pen(chosen?Palette.Accent:Color.FromArgb(200,204,215),chosen?2:1);
            graphics.DrawBezier(pen,start,new PointF(start.X+bend,start.Y),new PointF(end.X-bend*.4f,end.Y),end);
            if(chosen){using var brush=new SolidBrush(Palette.Accent);graphics.FillEllipse(brush,start.X-3,start.Y-3,6,6);float direction=left?-1:1;graphics.FillPolygon(brush,[end,new(end.X-direction*6,end.Y-4),new(end.X-direction*6,end.Y+4)]);}
        }
    }
    internal void VerifyLayout()
    {
        if(model==null||cards.Count!=model.Buttons.Count)throw new InvalidOperationException("Mapping cards do not match the remote layout.");
        foreach(var card in cards)if(card.Top<0||card.Bottom>Height||card.Left<0||card.Right>Width||card.Height<32)throw new InvalidOperationException("A mapping card is clipped: "+card.Control.Label);
    }
}

internal sealed class MappingCard:Panel
{
    internal LayoutControl Control { get; }
    private readonly InlineButton name,link;
    private readonly WorkspacePicker picker=new(){DropDownStyle=ComboBoxStyle.DropDownList,ItemHeight=16,Font=WorkspaceStyle.Text(8.75f),Margin=Padding.Empty};
    private string signature="";
    private bool learning;
    public event Action? Choose;
    public event Action<ActionKind>? Assign;
    public event Action<bool>? Link;
    private sealed record Choice(ActionKind Action,string Title);
    public MappingCard(LayoutControl control)
    {
        Control=control;DoubleBuffered=true;BackColor=Color.White;
        name=new InlineButton{Text=control.Label,Font=WorkspaceStyle.Text(9,true),AccessibleName="Select "+control.Label};name.Click+=(_,_)=>Choose?.Invoke();
        link=new InlineButton{Text="Link",Font=WorkspaceStyle.Text(8.5f),ForeColor=Palette.Muted};link.Click+=(_,_)=>Link?.Invoke(learning);
        picker.AccessibleName="Action when pressing "+control.Label;picker.DisplayMember="Title";picker.BindingContext=new BindingContext();
        picker.SelectionChangeCommitted+=(_,_)=>CommitSelection();Controls.AddRange([name,link,picker]);
    }
    private void CommitSelection(){if(picker.SelectedItem is Choice choice)Assign?.Invoke(choice.Action);}
    internal void ChooseActionForVerification(ActionKind action){picker.SelectedItem=((List<Choice>)picker.DataSource!).First(choice=>choice.Action==action);CommitSelection();}
    public void UpdateBinding(RemoteBinding? binding,ActionKind[] actions,bool selected,bool learning,bool anyLearning,HashSet<Usage> active,string shortcut,string? appName)
    {
        this.learning=learning;bool live=binding?.Usage is Usage usage&&active.Contains(usage);
        BackColor=live?Color.FromArgb(229,247,243):selected?Color.FromArgb(239,237,253):Color.White;
        border=live?Palette.Teal:selected?Palette.Accent:Palette.Border;chosen=selected||live;name.ForeColor=live?Palette.Teal:selected?Palette.Accent:Palette.Ink;
        var choices=actions.Select(action=>new Choice(action,action switch{ActionKind.Dictate when shortcut.Length>0=>"Dictation · "+shortcut,ActionKind.Focus when binding?.Action==ActionKind.Focus=>binding.LaunchApps is {Count:>1} targets?$"Cycle apps · {targets.Count} apps":"Open app · "+(appName??"Choose app…"),_=>MainWindow.ActionTitle(action)})).ToList();
        string next=string.Join('|',choices.Select(choice=>choice.Title));
        if(signature!=next){picker.DataSource=choices;signature=next;}
        var items=(List<Choice>)picker.DataSource!;var selectedChoice=items.FirstOrDefault(choice=>choice.Action==(binding?.Action??ActionKind.Native));
        if(!Equals(picker.SelectedItem,selectedChoice))picker.SelectedItem=selectedChoice;
        picker.Enabled=!anyLearning;link.Text=learning?"Cancel":binding?.Usage==null?"Link":"Relink";link.Enabled=!anyLearning||learning;link.ForeColor=learning?Color.DarkOrange:Palette.Muted;link.AccessibleName=link.Text+" "+Control.Label;Invalidate();name.Invalidate();
    }
    private Color border=Palette.Border;
    private bool chosen;
    protected override void OnPaintBackground(PaintEventArgs e)=>WorkspaceStyle.FillBackground(e.Graphics,Palette.Background,ClientRectangle);
    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;using var path=Palette.Round(new RectangleF(.5f,.5f,Width-1,Height-1),10);using var fill=new SolidBrush(BackColor);using var pen=new Pen(border,chosen?1.5f:1);e.Graphics.FillPath(fill,path);e.Graphics.DrawPath(pen,path);
    }
    protected override void OnLayout(LayoutEventArgs e)
    {
        base.OnLayout(e);float scale=DeviceDpi/96f;bool compact=Height<48*scale;
        int top=compact?16:20;name.Bounds=new Rectangle(7,1,Math.Max(30,Width-58),top);link.Bounds=new Rectangle(Width-49,1,43,top);
        picker.ItemHeight=compact?12:16;picker.Bounds=new Rectangle(7,top+1,Math.Max(20,Width-14),compact?18:22);
    }
}

internal sealed class InlineButton:PaintedButton
{
    private bool hovered;
    public InlineButton(){Cursor=Cursors.Hand;ForeColor=Palette.Ink;}
    protected override void OnMouseEnter(EventArgs e){hovered=true;Invalidate();base.OnMouseEnter(e);}
    protected override void OnMouseLeave(EventArgs e){hovered=false;Invalidate();base.OnMouseLeave(e);}
    protected override void OnPaintBackground(PaintEventArgs e)=>WorkspaceStyle.FillBackground(e.Graphics,WorkspaceStyle.SurfaceColor(Parent),ClientRectangle);
    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
        if(hovered&&Enabled){using var shape=Palette.Round(new RectangleF(0,1,Width,Height-2),4);using var fill=new SolidBrush(Color.FromArgb(232,228,250));e.Graphics.FillPath(fill,shape);}
        WorkspaceStyle.DrawText(e.Graphics,Text,Font,ClientRectangle,Enabled?hovered?Palette.Accent:ForeColor:Palette.Muted);
        if(Focused&&ShowFocusCues){using var shape=Palette.Round(new RectangleF(1,1,Width-2,Height-2),4);using var pen=new Pen(Palette.Accent);e.Graphics.DrawPath(pen,shape);}
    }
}

internal sealed class AppProfileSelector:FlowLayoutPanel
{
    private string signature="";
    public event Action<string>? Selected;
    internal void ChooseProfileForVerification(string id)=>Controls.OfType<AppProfileButton>().First(button=>Equals(button.Tag,id)).PerformClick();
    public AppProfileSelector(){FlowDirection=FlowDirection.LeftToRight;WrapContents=false;AutoScroll=true;BackColor=Color.Transparent;Margin=Padding.Empty;AccessibleName="App profiles";}
    public void UpdateChoices(IEnumerable<PluginManifest> choices,Configuration config)
    {
        var apps=choices.ToArray();string next=config.AppPluginID+"|"+config.TargetAppPath+"|"+string.Join('|',apps.Select(app=>app.Id+app.Name+(config.AppMappings.GetValueOrDefault(AppRouting.Key(config.DevicePluginID,app.Id))?.TargetAppPath??"")));if(next==signature)return;signature=next;
        foreach(Control child in Controls.Cast<Control>().ToArray())child.Dispose();Controls.Clear();
        foreach(var app in apps)
        {
            string path=app.Id==config.AppPluginID?config.TargetAppPath:config.AppMappings.GetValueOrDefault(AppRouting.Key(config.DevicePluginID,app.Id))?.TargetAppPath??"";
            var button=new AppProfileButton(app,app.Id==config.AppPluginID,path){Tag=app.Id};button.Click+=(_,_)=>Selected?.Invoke(app.Id);Controls.Add(button);
        }
    }
}

internal sealed class AppProfileButton:PaintedButton
{
    private readonly bool selected;
    private readonly Image? icon;
    private readonly bool shared;
    private bool hovered;
    public AppProfileButton(PluginManifest app,bool selected,string path)
    {
        this.selected=selected;shared=app.Id==Configuration.NoSpecificAppID;Text=app.Name;AccessibleName=app.Name;AccessibleDescription=selected?"Selected app profile":"Choose app profile";Size=new Size(100,82);Margin=new Padding(0,0,8,0);Cursor=Cursors.Hand;Font=WorkspaceStyle.Text(9,selected);
        try{if(File.Exists(path)){using var associated=Icon.ExtractAssociatedIcon(path);icon=associated?.ToBitmap();}}catch(Exception error) when(error is IOException or ArgumentException or System.ComponentModel.Win32Exception){ }
    }
    protected override void OnPaintBackground(PaintEventArgs e)=>WorkspaceStyle.FillBackground(e.Graphics,Palette.Background,ClientRectangle);
    protected override void OnMouseEnter(EventArgs e){hovered=true;Invalidate();base.OnMouseEnter(e);}
    protected override void OnMouseLeave(EventArgs e){hovered=false;Invalidate();base.OnMouseLeave(e);}
    protected override void OnPaint(PaintEventArgs e)
    {
        var g=e.Graphics;g.SmoothingMode=SmoothingMode.AntiAlias;float scale=DeviceDpi/96f;
        if(selected||hovered){using var shape=Palette.Round(new RectangleF(1,1,Width-2,Height-2),12);using var fill=new SolidBrush(selected?Color.FromArgb(234,231,252):Color.FromArgb(241,239,249));using var pen=new Pen(selected?Color.FromArgb(195,186,238):Palette.Border);g.FillPath(fill,shape);g.DrawPath(pen,shape);}
        var r=new Rectangle((Width-(int)(36*scale))/2,(int)(9*scale),(int)(36*scale),(int)(36*scale));
        if(icon!=null)g.DrawImage(icon,r);
        else
        {
            using var shape=Palette.Round(r,9);using var fill=new SolidBrush(shared?Color.FromArgb(225,229,238):Color.FromArgb(229,224,250));g.FillPath(fill,shape);
            if(shared){using var pen=new Pen(Palette.Muted,1.5f);for(int i=0;i<4;i++)g.DrawRectangle(pen,r.X+9+i%2*11,r.Y+9+i/2*11,7,7);}
            else WorkspaceStyle.DrawText(g,Text[..1],WorkspaceStyle.Text(15,true),r,Palette.Accent,TextFormatFlags.HorizontalCenter|TextFormatFlags.VerticalCenter|TextFormatFlags.SingleLine);
        }
        WorkspaceStyle.DrawText(g,Text,Font,new Rectangle(3,(int)(52*scale),Width-6,(int)(22*scale)),selected?Palette.Accent:Palette.Ink,TextFormatFlags.HorizontalCenter|TextFormatFlags.VerticalCenter|TextFormatFlags.SingleLine|TextFormatFlags.EndEllipsis);
        if(Focused&&ShowFocusCues){using var focus=Palette.Round(new RectangleF(3,3,Width-6,Height-6),9);using var pen=new Pen(Palette.Accent,1.5f);g.DrawPath(pen,focus);}
    }
    protected override void Dispose(bool disposing){if(disposing)icon?.Dispose();base.Dispose(disposing);}
}
