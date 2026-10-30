using System.Drawing.Drawing2D;
using System.Drawing.Text;
using System.Runtime.InteropServices;
namespace JustVibeRemote;

internal static class WorkspaceStyle
{
    public const int Tight=4, Related=8, Controls=12, Section=16, Page=24, CardInset=24, Inset=28;
    private static readonly PrivateFontCollection fonts=new();
    private static readonly Dictionary<(bool,float,bool,GraphicsUnit),Font> cache=[];
    static WorkspaceStyle()
    {
        foreach(var name in new[]{"Manrope-Bold.ttf","Inter-Regular.ttf","Inter-Bold.ttf"})
        {
            var path=Path.Combine(AppContext.BaseDirectory,"Fonts",name);
            if(!File.Exists(path))continue;
            fonts.AddFontFile(path);AddFontResourceEx(path,0x10,0);
        }
    }
    public static Font Text(float size=10,bool bold=false,bool heading=false,GraphicsUnit unit=GraphicsUnit.Point)
    {
        var key=(heading,size,bold,unit);
        if(cache.TryGetValue(key,out var cached))return cached;
        var family=fonts.Families.FirstOrDefault(f=>f.Name==(heading?"JustVibe Manrope":"JustVibe Inter"));
        var style=bold||heading?FontStyle.Bold:FontStyle.Regular;
        return cache[key]=family!=null?new Font(family,size,style,unit):new Font("Segoe UI",size,style,unit);
    }
    public static void Apply(Control control)
    {
        if(control is not System.Windows.Forms.Label)control.Font=Text(control.Font.Size,control.Font.Bold);
        foreach(Control child in control.Controls)Apply(child);
    }
    public static Label Label(string text,float size=10,bool bold=false,bool heading=false,int width=700)=>new()
    {Text=text,AutoSize=true,UseCompatibleTextRendering=true,MaximumSize=new Size(width,0),Font=Text(size,bold,heading),ForeColor=bold||heading?Palette.Ink:Palette.Muted,BackColor=Color.Transparent,Margin=new Padding(0,0,0,Controls)};
    public static Button Button(string text,Action action,bool primary=false)
    {
        var button=new Button{Text=text,AutoSize=true,Font=Text(10,primary),FlatStyle=FlatStyle.Flat,BackColor=primary?Palette.Accent:Color.White,ForeColor=primary?Color.White:Palette.Ink,Padding=new Padding(Controls,Related,Controls,Related),Margin=new Padding(0,0,Controls,Controls),Cursor=Cursors.Hand,MinimumSize=new Size(0,36)};
        button.FlatAppearance.BorderColor=Color.FromArgb(224,224,235);button.FlatAppearance.BorderSize=primary?0:1;button.Click+=(_,_)=>action();return button;
    }
    public static FlowLayoutPanel Stack(int width=700)=>new(){AutoSize=true,AutoSizeMode=AutoSizeMode.GrowAndShrink,FlowDirection=FlowDirection.TopDown,WrapContents=false,Width=width,BackColor=Color.Transparent,Margin=Padding.Empty};
    public static FlowLayoutPanel Row(params Control[] controls)
    {var row=new FlowLayoutPanel{AutoSize=true,WrapContents=true,MaximumSize=new Size(1000,0),BackColor=Color.Transparent,Margin=new Padding(0,0,0,Controls)};row.Controls.AddRange(controls);return row;}
    public static Panel Card(params Control[] controls)
    {
        var stack=Stack();stack.Controls.AddRange(controls);stack.BackColor=Color.White;
        var card=new RoundedCard{AutoSize=true,AutoSizeMode=AutoSizeMode.GrowAndShrink,Padding=new Padding(CardInset),Margin=new Padding(0,0,0,Page)};
        card.Controls.Add(stack);stack.Location=new Point(CardInset,CardInset);return card;
    }
    public static void Open(string target)=>System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(target){UseShellExecute=true});
    [DllImport("gdi32.dll",CharSet=CharSet.Unicode)]private static extern int AddFontResourceEx(string name,uint flags,nint reserved);
}
internal sealed class RoundedCard:Panel
{
    public RoundedCard(){DoubleBuffered=true;BackColor=Palette.Background;}
    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
        if(Width<2||Height<2)return;
        using var path=Palette.Round(new RectangleF(.5f,.5f,Width-1,Height-1),18);
        e.Graphics.FillPath(Brushes.White,path);using var pen=new Pen(Color.FromArgb(224,224,235));e.Graphics.DrawPath(pen,path);
    }
}
internal sealed class SidebarSurface:Panel
{
    public SidebarSurface(){DoubleBuffered=true;}
    protected override void OnPaintBackground(PaintEventArgs e)
    {using var brush=new LinearGradientBrush(ClientRectangle,Color.FromArgb(236,230,249),Color.FromArgb(250,250,252),90);e.Graphics.FillRectangle(brush,ClientRectangle);}
}
internal sealed class NavigationButton:Button
{
    [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
    internal bool Selected { get; set; }
    private bool hovered;
    private readonly int icon;
    public NavigationButton(string text,int icon,Action action)
    {Text=text;this.icon=icon;Size=new Size(212,38);Margin=new Padding(0,0,0,3);FlatStyle=FlatStyle.Flat;FlatAppearance.BorderSize=0;Font=WorkspaceStyle.Text(10);AccessibleName=text;Click+=(_,_)=>action();}
    protected override void OnMouseEnter(EventArgs e){hovered=true;Invalidate();base.OnMouseEnter(e);}
    protected override void OnMouseLeave(EventArgs e){hovered=false;Invalidate();base.OnMouseLeave(e);}
    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
        if(Selected||hovered){using var shape=Palette.Round(new RectangleF(4,2,Width-8,Height-4),8);using var fill=new SolidBrush(Selected?Color.FromArgb(226,221,240):Color.FromArgb(235,233,242));e.Graphics.FillPath(fill,shape);}
        float scale=DeviceDpi/96f;var graphicsState=e.Graphics.Save();e.Graphics.ScaleTransform(scale,scale);e.Graphics.TranslateTransform(0,-3);
        using var pen=new Pen(Color.FromArgb(95,96,105),1.6f);
        var r=new Rectangle(14,13,18,18);
        if(icon is 0 or 5){e.Graphics.DrawRectangle(pen,r);e.Graphics.DrawLine(pen,19,18,27,18);e.Graphics.DrawLine(pen,19,23,27,23);}
        else if(icon is 1 or 2 or 6){for(int i=0;i<4;i++)e.Graphics.DrawRectangle(pen,14+i%2*10,13+i/2*10,6,6);}
        else if(icon==4){e.Graphics.DrawEllipse(pen,20,12,6,14);e.Graphics.DrawArc(pen,16,16,14,14,0,180);e.Graphics.DrawLine(pen,23,30,23,33);}
        else{e.Graphics.DrawEllipse(pen,r);e.Graphics.DrawLine(pen,23,18,23,24);e.Graphics.DrawEllipse(pen,22,27,1,1);}
        e.Graphics.Restore(graphicsState);
        TextRenderer.DrawText(e.Graphics,Text,Font,new Rectangle((int)(46*scale),0,Math.Max(1,Width-(int)(54*scale)),Height),Palette.Ink,TextFormatFlags.Left|TextFormatFlags.VerticalCenter|TextFormatFlags.EndEllipsis);
        if(Focused)ControlPaint.DrawFocusRectangle(e.Graphics,new Rectangle(3,3,Width-6,Height-6));
    }
}
