using System.Drawing.Drawing2D;
using JustVibeRemote.Core;

namespace JustVibeRemote;

internal static class Palette
{
    public static readonly Color Accent=Color.FromArgb(92,82,224), Ink=Color.FromArgb(36,41,59), Muted=Color.FromArgb(102,112,135), Background=Color.FromArgb(246,247,250), Teal=Color.FromArgb(15,127,108), Sidebar=Color.FromArgb(241,237,250), Border=Color.FromArgb(224,227,237);
    public static readonly Color AccentHover=Color.FromArgb(81,70,209),AccentPressed=Color.FromArgb(69,58,187),InputBorder=Color.FromArgb(203,209,222),BorderHover=Color.FromArgb(166,175,195),FieldDisabled=Color.FromArgb(242,244,248);
    public static GraphicsPath Round(RectangleF r,float radius)
    {
        float d=Math.Min(radius*2,Math.Min(r.Width,r.Height));var path=new GraphicsPath();
        path.AddArc(r.X,r.Y,d,d,180,90);path.AddArc(r.Right-d,r.Y,d,d,270,90);path.AddArc(r.Right-d,r.Bottom-d,d,d,0,90);path.AddArc(r.X,r.Bottom-d,d,d,90,90);path.CloseFigure();return path;
    }
}
internal sealed class RemoteCanvas : Panel
{
    private RemoteLayout? model;
    private readonly List<RemoteGraphicButton> buttons=[];
    private readonly ToolTip hints=new();
    internal Action<Graphics>? ConnectionPainter;
    internal Point? CenterOf(string id)
    {
        var button=buttons.FirstOrDefault(button=>button.Control.Id==id);return button==null?null:new Point(button.Left+button.Width/2,button.Top+button.Height/2);
    }
    public event Action<string>? Selected;
    public RemoteCanvas() { DoubleBuffered=true;BackColor=Color.White; }
    public void UpdateRemote(RemoteLayout layout,List<JustVibeRemote.Core.Binding> bindings,string? selected,HashSet<Usage> active)
    {
        bool same=model!=null && model.Width==layout.Width && model.Height==layout.Height && model.BodyStyle==layout.BodyStyle && model.Dpad==layout.Dpad && model.Buttons.SequenceEqual(layout.Buttons);
        if (!same)
        {
            foreach(var button in buttons)button.Dispose();buttons.Clear();model=layout;
            foreach(var control in layout.Buttons.OrderBy(b=>b.Bounds.Y).ThenBy(b=>b.Bounds.X))
            {
                var button=new RemoteGraphicButton(control);button.Click+=(_,_)=>Selected?.Invoke(control.Id);buttons.Add(button);Controls.Add(button);
            }
            PositionButtons();
        }
        foreach(var button in buttons)
        {
            var binding=bindings.FirstOrDefault(b=>b.ControlID==button.Control.Id || button.Control.Id.StartsWith("button-") && b.Name==button.Control.Label);
            button.Chosen=button.Control.Id==selected;button.Learned=binding?.Usage!=null;button.Live=binding?.Usage is Usage usage && active.Contains(usage);
            hints.SetToolTip(button,$"{button.Control.Label} · {(button.Learned?"Linked":"Not learned")} · Click to configure");button.Invalidate();
        }
        Invalidate();
    }
    private (float Scale,float X,float Y) Transform()
    {
        if(model==null)return(1,0,0);float scale=(float)Math.Min((ClientSize.Width-52)/model.Width,(ClientSize.Height-28)/model.Height);
        scale=Math.Max(.1f,scale);return(scale,(ClientSize.Width-(float)model.Width*scale)/2,(ClientSize.Height-(float)model.Height*scale)/2);
    }
    protected override void OnResize(EventArgs e) { base.OnResize(e);PositionButtons();Invalidate(); }
    private void PositionButtons()
    {
        var(s,x,y)=Transform();foreach(var button in buttons) { var b=button.Control.Bounds;button.Bounds=Rectangle.Round(new RectangleF(x+(float)b.X*s,y+(float)b.Y*s,(float)b.Width*s,(float)b.Height*s)); }
    }
    protected override void OnPaint(PaintEventArgs e)
    {
        PaintSurface(e.Graphics);
    }
    internal void PaintSurface(Graphics g)
    {
        WorkspaceStyle.FillBackground(g,BackColor,ClientRectangle);if(model==null)return;g.SmoothingMode=SmoothingMode.AntiAlias;var state=g.Save();var(s,x,y)=Transform();g.TranslateTransform(x,y);g.ScaleTransform(s,s);
        var rect=new RectangleF(0,0,(float)model.Width,(float)model.Height);
        using(var shadow=Palette.Round(new RectangleF(5,9,rect.Width,rect.Height),18))using(var fill=new SolidBrush(Color.FromArgb(15,20,30,45)))g.FillPath(fill,shadow);
        using(var body=Palette.Round(rect,18))using(var metal=new LinearGradientBrush(rect,Color.Gray,Color.Silver,0f))
        {
            metal.InterpolationColors=model.BodyStyle=="silver"?new ColorBlend{Colors=[Color.FromArgb(80,84,88),Color.FromArgb(220,223,222),Color.FromArgb(158,165,164),Color.FromArgb(203,207,206),Color.FromArgb(78,82,86)],Positions=[0,.16f,.48f,.85f,1]}:new ColorBlend{Colors=[Color.FromArgb(38,42,48),Color.FromArgb(60,64,70),Color.FromArgb(32,35,40)],Positions=[0,.5f,1]};
            g.FillPath(metal,body);using var outline=new Pen(Color.FromArgb(40,44,49),2);g.DrawPath(outline,body);
        }
        using(var face=Palette.Round(new RectangleF(18,30,rect.Width-36,Math.Min(rect.Height-60,528)),25))using(var fill=new LinearGradientBrush(new RectangleF(18,30,rect.Width-36,528),Color.FromArgb(34,36,40),Color.FromArgb(18,20,23),90f))g.FillPath(fill,face);
        if(model.Dpad is { } d)
        {
            var ring=new RectangleF((float)(d.X-d.Radius),(float)(d.Y-d.Radius),(float)d.Radius*2,(float)d.Radius*2);
            using var fill=new LinearGradientBrush(ring,Color.FromArgb(65,67,73),Color.FromArgb(38,40,46),90f);g.FillEllipse(fill,ring);using var pen=new Pen(Color.FromArgb(20,22,26),2);g.DrawEllipse(pen,ring);
        }
        using(var ink=new SolidBrush(Color.FromArgb(80,30,35,40)))using(var format=new StringFormat{Alignment=StringAlignment.Center})
        {
            // This marking is part of the scaled illustration, not a UI label.
            g.TextRenderingHint=System.Drawing.Text.TextRenderingHint.AntiAliasGridFit;
            g.DrawString("R E M O T E V I B E",WorkspaceStyle.Text(9,true),ink,new RectangleF(0,rect.Height-65,rect.Width,30),format);
        }
        g.Restore(state);
        ConnectionPainter?.Invoke(g);
    }
    protected override void Dispose(bool disposing){if(disposing)hints.Dispose();base.Dispose(disposing);}
}
internal sealed class RemoteGraphicButton : PaintedButton
{
    public LayoutControl Control{get;}
    [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
    internal bool Chosen{get;set;}
    [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
    internal bool Learned{get;set;}
    [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
    internal bool Live{get;set;}
    private bool hovered;
    public RemoteGraphicButton(LayoutControl control)
    {
        Control=control;BackColor=Color.Transparent;AccessibleName=control.Label;AccessibleDescription="Select this physical button to learn its signal and change its action.";
        SetStyle(ControlStyles.SupportsTransparentBackColor|ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer,true);
        MouseEnter+=(_,_)=>{hovered=true;Invalidate();};MouseLeave+=(_,_)=>{hovered=false;Invalidate();};
    }
    protected override void OnPaintBackground(PaintEventArgs e)
    {
        // ButtonBase paints a themed button (including text) here even when
        // OnPaint is overridden. Repaint only the remote beneath this control.
        if(Parent is RemoteCanvas canvas)
        {
            var state=e.Graphics.Save();e.Graphics.TranslateTransform(-Left,-Top);canvas.PaintSurface(e.Graphics);e.Graphics.Restore(state);
        }
        else WorkspaceStyle.FillBackground(e.Graphics,Palette.Background,ClientRectangle);
    }
    protected override void OnPaint(PaintEventArgs e)
    {
        var g=e.Graphics;g.SmoothingMode=SmoothingMode.AntiAlias;var r=new RectangleF(2,2,Width-4,Height-4);if(r.Width<=0 || r.Height<=0)return;
        using var path=Palette.Round(r,Control.Shape is "circle" or "pill"?Math.Min(r.Width,r.Height)/2:7);
        bool bright=Chosen||Live;Color background=bright?Live?Palette.Teal:Palette.Accent:Control.Shape=="pill"?Color.FromArgb(246,247,250):Color.FromArgb(hovered?64:47,hovered?67:50,hovered?74:57);
        if(Control.Shape!="segment" || bright || hovered){using var fill=new SolidBrush(background);g.FillPath(fill,path);}
        if(Chosen||Focused){using var outline=new Pen(Color.FromArgb(186,195,255),2);g.DrawPath(outline,path);}
        Color color=bright?Color.White:Control.Shape=="pill"?Palette.Ink:Control.Icon=="power"?Color.FromArgb(233,101,109):Control.Icon=="microphone"?Color.FromArgb(150,171,255):Color.White;
        float cx=r.X+r.Width/2,cy=r.Y+r.Height/2;
        using var pen=new Pen(color,Math.Max(1.2f,r.Width/26)){StartCap=LineCap.Round,EndCap=LineCap.Round};
        using var ink=new SolidBrush(color);
        if(Control.Icon=="microphone")
        {
            float w=r.Width*.22f;using var cap=Palette.Round(new RectangleF(cx-w/2,cy-w*1.1f,w,w*1.5f),w/2);g.DrawPath(pen,cap);g.DrawArc(pen,cx-w*.85f,cy-w*.55f,w*1.7f,w*1.4f,0,180);g.DrawLine(pen,cx,cy+w*.7f,cx,cy+w*1.2f);g.DrawLine(pen,cx-w*.4f,cy+w*1.2f,cx+w*.4f,cy+w*1.2f);
        }
        else if(Control.Icon=="power"){float d=Math.Min(r.Width,r.Height)*.48f;g.DrawArc(pen,cx-d/2,cy-d/2,d,d,-50,280);g.DrawLine(pen,cx,cy-d*.65f,cx,cy);}
        else if(Control.Icon is "up" or "down" or "left" or "right")
        {
            float a=Math.Min(r.Width,r.Height)*.22f;PointF[] points=Control.Icon switch{"up"=>[new(cx,cy-a),new(cx-a,cy+a),new(cx+a,cy+a)],"down"=>[new(cx,cy+a),new(cx-a,cy-a),new(cx+a,cy-a)],"left"=>[new(cx-a,cy),new(cx+a,cy-a),new(cx+a,cy+a)],_=>[new(cx+a,cy),new(cx-a,cy-a),new(cx-a,cy+a)]};g.FillPolygon(ink,points);
        }
        else if(Control.Icon=="menu"){float a=r.Width*.22f;for(int i=-1;i<=1;i++)g.DrawLine(pen,cx-a,cy+i*a*.6f,cx+a,cy+i*a*.6f);}
        else
        {
            string text=Control.Text??Control.Icon switch{"mode"=>"◎","ok"=>"OK","home-back"=>"⌂↶","home"=>"⌂","back"=>"↶","volume-up"=>"V +","volume-down"=>"V −","page-up"=>"PG +","page-down"=>"PG −","apps"=>"Apps",_=>Control.Label};
            float size=Control.Shape=="pill"?Math.Clamp(r.Width/7,7,11):Math.Clamp(r.Width/4,8,14);var font=WorkspaceStyle.Text(size,true,false,GraphicsUnit.Pixel);WorkspaceStyle.DrawText(g,text,font,Rectangle.Round(r),color,TextFormatFlags.HorizontalCenter|TextFormatFlags.VerticalCenter|TextFormatFlags.SingleLine|TextFormatFlags.NoPadding);
        }
        if(Learned&&!Chosen&&Control.Shape!="segment"){using var dot=new SolidBrush(Palette.Teal);g.FillEllipse(dot,r.Right-6,r.Bottom-6,4,4);}
    }
}
