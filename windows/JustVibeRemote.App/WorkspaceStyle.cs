using System.Drawing.Drawing2D;
namespace JustVibeRemote;

internal static class WorkspaceStyle
{
    public const int Tight=4, Related=8, Controls=12, Section=16, Page=24, CardInset=24, Inset=28;
    private static readonly Dictionary<(bool,float,bool,GraphicsUnit),Font> cache=[];
    public static Font Text(float size=10,bool bold=false,bool heading=false,GraphicsUnit unit=GraphicsUnit.Point)
    {
        var key=(heading,size,bold,unit);
        if(cache.TryGetValue(key,out var cached))return cached;
        return cache[key]=new Font(bold||heading?"Segoe UI Semibold":"Segoe UI",size,FontStyle.Regular,unit);
    }
    public static void Apply(Control control)
    {
        if(control is Label label){label.UseCompatibleTextRendering=false;label.UseMnemonic=false;}
        else control.Font=Text(control.Font.Size,control.Font.Bold||control.Font.Name=="Segoe UI Semibold");
        if(control is CheckBox check){check.Font=Text(10);check.ForeColor=Palette.Ink;check.FlatStyle=FlatStyle.Standard;check.UseVisualStyleBackColor=true;}
        if(control is TextBox textBox&&textBox.Parent is not WorkspaceTextBox){textBox.BorderStyle=BorderStyle.FixedSingle;textBox.BackColor=Color.White;textBox.ForeColor=Palette.Ink;if(textBox.Multiline)textBox.Font=new Font("Consolas",9);}
        if(control is CheckedListBox checkedList){checkedList.BorderStyle=BorderStyle.FixedSingle;checkedList.BackColor=Color.White;checkedList.ForeColor=Palette.Ink;checkedList.ItemHeight=26;}
        foreach(Control child in control.Controls)Apply(child);
    }
    public static Label Label(string text,float size=10,bool bold=false,bool heading=false,int width=700)=>new()
    {Text=text,AutoSize=true,UseCompatibleTextRendering=false,UseMnemonic=false,MaximumSize=new Size(width,0),Font=Text(size,bold,heading),ForeColor=bold||heading?Palette.Ink:Palette.Muted,BackColor=Color.Transparent,Margin=new Padding(0,0,0,Related)};
    public static WorkspaceButton Button(string text,Action action,bool primary=false)
    {
        var button=new WorkspaceButton(primary){Text=text,AutoSize=true,Font=Text(10,primary),Padding=new Padding(16,0,16,0),Margin=new Padding(0,0,Controls,Related),Cursor=Cursors.Hand,MinimumSize=new Size(0,38)};
        button.Click+=(_,_)=>action();return button;
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
    public static Color SurfaceColor(Control? control)
    {
        for(var parent=control;parent!=null;parent=parent.Parent)if(parent.BackColor.A==255)return parent.BackColor;
        return Palette.Background;
    }
    public static void DrawText(Graphics graphics,string text,Font font,Rectangle bounds,Color color,TextFormatFlags flags=TextFormatFlags.Left|TextFormatFlags.VerticalCenter|TextFormatFlags.SingleLine|TextFormatFlags.EndEllipsis)
        =>TextRenderer.DrawText(graphics,text,font,bounds,color,flags|TextFormatFlags.NoPrefix|TextFormatFlags.PreserveGraphicsClipping);
    public static void FillBackground(Graphics graphics,Color color,Rectangle bounds){using var fill=new SolidBrush(color);graphics.FillRectangle(fill,bounds);}
}
internal sealed class RoundedCard:Panel
{
    public RoundedCard(){DoubleBuffered=true;BackColor=Palette.Background;}
    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
        if(Width<2||Height<2)return;
        using var path=Palette.Round(new RectangleF(.5f,.5f,Width-1,Height-1),18);
        e.Graphics.FillPath(Brushes.White,path);using var pen=new Pen(Palette.Border);e.Graphics.DrawPath(pen,path);
    }
}
internal sealed class SidebarSurface:Panel
{
    public SidebarSurface(){DoubleBuffered=true;}
    protected override void OnPaintBackground(PaintEventArgs e)
    {WorkspaceStyle.FillBackground(e.Graphics,Palette.Sidebar,ClientRectangle);}
}
// A native BUTTON class paints its own themed surface during WM_PRINT as well
// as owner drawing. Use a managed control for a single, consistent paint path.
internal class PaintedButton:Control
{
    private bool keyboardPressed;
    public PaintedButton(){SetStyle(ControlStyles.SupportsTransparentBackColor|ControlStyles.Selectable|ControlStyles.StandardClick|ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer,true);TabStop=true;AccessibleRole=AccessibleRole.PushButton;}
    public void PerformClick(){if(Enabled)OnClick(EventArgs.Empty);}
    protected override void OnTextChanged(EventArgs e)
    {
        base.OnTextChanged(e);
        if(AutoSize){Size=GetPreferredSize(Size.Empty);Parent?.PerformLayout(this,nameof(Text));}
        Invalidate();
    }
    protected override bool IsInputKey(Keys keyData)=>(keyData&Keys.KeyCode) is Keys.Space or Keys.Enter||base.IsInputKey(keyData);
    protected override void OnKeyDown(KeyEventArgs e){if(e.KeyCode is Keys.Space or Keys.Enter){keyboardPressed=true;e.Handled=true;}base.OnKeyDown(e);}
    protected override void OnKeyPress(KeyPressEventArgs e){if(e.KeyChar is ' ' or '\r')e.Handled=true;base.OnKeyPress(e);}
    protected override void OnKeyUp(KeyEventArgs e){if(e.KeyCode is Keys.Space or Keys.Enter){bool activate=keyboardPressed;keyboardPressed=false;if(activate)PerformClick();e.Handled=true;}base.OnKeyUp(e);}
    protected override void OnGotFocus(EventArgs e){base.OnGotFocus(e);Invalidate();}
    protected override void OnLostFocus(EventArgs e){keyboardPressed=false;base.OnLostFocus(e);Invalidate();}
    public override Size GetPreferredSize(Size proposedSize)
    {
        var text=TextRenderer.MeasureText(Text,Font,Size.Empty,TextFormatFlags.SingleLine|TextFormatFlags.NoPrefix);return new Size(Math.Max(MinimumSize.Width,text.Width+Padding.Horizontal+8),Math.Max(MinimumSize.Height,text.Height+Padding.Vertical+8));
    }
    protected override AccessibleObject CreateAccessibilityInstance()=>new PaintedButtonAccessibility(this);
    private sealed class PaintedButtonAccessibility(PaintedButton owner):ControlAccessibleObject(owner)
    {
        public override string DefaultAction=>"Press";
        public override void DoDefaultAction()=>owner.PerformClick();
    }
}

internal sealed class NavigationButton:PaintedButton
{
    [System.ComponentModel.DesignerSerializationVisibility(System.ComponentModel.DesignerSerializationVisibility.Hidden)]
    internal bool Selected { get; set; }
    private bool hovered;
    private readonly int icon;
    public NavigationButton(string text,int icon,Action action)
    {Text=text;this.icon=icon;Size=new Size(208,42);Margin=new Padding(0,0,0,4);Font=WorkspaceStyle.Text(10);AccessibleName=text;Cursor=Cursors.Hand;BackColor=Palette.Sidebar;SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer,true);Click+=(_,_)=>action();}
    protected override void OnPaintBackground(PaintEventArgs e)=>WorkspaceStyle.FillBackground(e.Graphics,Palette.Sidebar,ClientRectangle);
    protected override void OnMouseEnter(EventArgs e){hovered=true;Invalidate();base.OnMouseEnter(e);}
    protected override void OnMouseLeave(EventArgs e){hovered=false;Invalidate();base.OnMouseLeave(e);}
    internal void PreviewHover(bool value){if(value)OnMouseEnter(EventArgs.Empty);else OnMouseLeave(EventArgs.Empty);}
    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
        if(Selected||hovered){using var shape=Palette.Round(new RectangleF(0,1,Width-1,Height-2),8);using var fill=new SolidBrush(Selected?Color.FromArgb(226,221,240):Color.FromArgb(235,231,245));e.Graphics.FillPath(fill,shape);}
        float scale=DeviceDpi/96f;var graphicsState=e.Graphics.Save();e.Graphics.ScaleTransform(scale,scale);e.Graphics.TranslateTransform(0,-3);
        using var pen=new Pen(Selected?Palette.Accent:Palette.Muted,1.6f);
        var r=new Rectangle(14,13,18,18);
        if(icon==0){using var outline=Palette.Round(new RectangleF(17,11,12,23),3);e.Graphics.DrawPath(pen,outline);e.Graphics.DrawEllipse(pen,20,15,6,6);e.Graphics.DrawLine(pen,21,26,25,26);e.Graphics.DrawLine(pen,21,29,25,29);}
        else if(icon is 1 or 2){for(int i=0;i<4;i++)e.Graphics.DrawRectangle(pen,14+i%2*10,13+i/2*10,6,6);}
        else if(icon==3){for(int i=0;i<9;i++)e.Graphics.DrawEllipse(pen,14+i%3*7,13+i/3*7,3,3);}
        else if(icon==4){for(int i=0;i<5;i++){int height=i==2?21:i%2==1?13:7;e.Graphics.DrawLine(pen,15+i*4,23-height/2,15+i*4,23+height/2);}}
        else if(icon==5){for(int i=0;i<3;i++){int y=15+i*7,x=i%2==0?20:27;e.Graphics.DrawLine(pen,14,y,32,y);e.Graphics.DrawEllipse(pen,x-2,y-2,4,4);}}
        else if(icon==6){e.Graphics.DrawRectangle(pen,r);e.Graphics.DrawEllipse(pen,20,9,6,6);e.Graphics.DrawEllipse(pen,29,19,6,6);}
        else{e.Graphics.DrawEllipse(pen,r);e.Graphics.DrawLine(pen,23,18,23,24);e.Graphics.DrawEllipse(pen,22,27,1,1);}
        e.Graphics.Restore(graphicsState);
        WorkspaceStyle.DrawText(e.Graphics,Text,Font,new Rectangle((int)(46*scale),0,Math.Max(1,Width-(int)(54*scale)),Height),Selected?Palette.Accent:Palette.Ink);
        if(Focused&&ShowFocusCues){using var focus=Palette.Round(new RectangleF(2,3,Width-5,Height-6),6);using var focusPen=new Pen(Palette.Accent,1.5f);e.Graphics.DrawPath(focusPen,focus);}
    }
}

internal sealed class WorkspaceButton:PaintedButton
{
    private readonly bool primary;
    private bool hovered,pressed;
    public WorkspaceButton(bool primary)
    {
        this.primary=primary;
        BackColor=primary?Palette.Accent:Color.White;ForeColor=primary?Color.White:Palette.Ink;
        SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer,true);
    }
    protected override void OnMouseEnter(EventArgs e){hovered=true;Invalidate();base.OnMouseEnter(e);}
    protected override void OnMouseLeave(EventArgs e){hovered=false;pressed=false;Invalidate();base.OnMouseLeave(e);}
    protected override void OnMouseDown(MouseEventArgs e){pressed=e.Button==MouseButtons.Left;Invalidate();base.OnMouseDown(e);}
    protected override void OnMouseUp(MouseEventArgs e){pressed=false;Invalidate();base.OnMouseUp(e);}
    protected override void OnMouseCaptureChanged(EventArgs e){pressed=false;Invalidate();base.OnMouseCaptureChanged(e);}
    protected override void OnKeyDown(KeyEventArgs e){if(e.KeyCode is Keys.Enter or Keys.Space){pressed=true;Invalidate();}base.OnKeyDown(e);}
    protected override void OnKeyUp(KeyEventArgs e){pressed=false;Invalidate();base.OnKeyUp(e);}
    protected override void OnPaintBackground(PaintEventArgs e)=>WorkspaceStyle.FillBackground(e.Graphics,WorkspaceStyle.SurfaceColor(Parent),ClientRectangle);
    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
        using var shape=Palette.Round(new RectangleF(.5f,.5f,Width-1,Height-1),7);
        var fill=primary?(pressed?Palette.AccentPressed:hovered?Palette.AccentHover:Palette.Accent):(pressed?Color.FromArgb(234,232,247):hovered?Color.FromArgb(247,246,253):Color.White);
        using var brush=new SolidBrush(Enabled?fill:Palette.FieldDisabled);e.Graphics.FillPath(brush,shape);
        if(!primary){using var pen=new Pen(hovered&&Enabled?Palette.BorderHover:Palette.InputBorder);e.Graphics.DrawPath(pen,shape);}
        WorkspaceStyle.DrawText(e.Graphics,Text,Font,new Rectangle(10,0,Width-20,Height),Enabled?ForeColor:Palette.Muted,TextFormatFlags.HorizontalCenter|TextFormatFlags.VerticalCenter|TextFormatFlags.SingleLine|TextFormatFlags.EndEllipsis);
        if(Focused&&ShowFocusCues){using var pen=new Pen(primary?Color.White:Palette.Accent,1.5f);using var focus=Palette.Round(new RectangleF(3,3,Width-7,Height-7),4);e.Graphics.DrawPath(pen,focus);}
    }
}

// Native data-bound pickers keep their keyboard/accessibility behavior; drawing
// the text ourselves also makes screenshots reflect what the user sees.
internal sealed class WorkspacePicker:ComboBox
{
    private bool hovered;
    public WorkspacePicker(){DrawMode=DrawMode.OwnerDrawFixed;ItemHeight=26;IntegralHeight=false;DropDownHeight=260;FlatStyle=FlatStyle.Flat;BackColor=Color.White;ForeColor=Palette.Ink;Margin=new Padding(0,0,12,12);}
    protected override void OnDrawItem(DrawItemEventArgs e)
    {
        bool selected=(e.State&DrawItemState.Selected)!=0;
        using var fill=new SolidBrush(selected?Color.FromArgb(229,235,255):Color.White);e.Graphics.FillRectangle(fill,e.Bounds);
        string text=(e.Index>=0&&e.Index<Items.Count?GetItemText(Items[e.Index]):Text)??"";
        WorkspaceStyle.DrawText(e.Graphics,text,e.Font??Font,new Rectangle(e.Bounds.X+6,e.Bounds.Y,e.Bounds.Width-9,e.Bounds.Height),Enabled?Palette.Ink:Palette.Muted);
        if((e.State&DrawItemState.Focus)!=0)e.DrawFocusRectangle();
    }
    protected override void OnMouseEnter(EventArgs e){hovered=true;Invalidate();base.OnMouseEnter(e);}
    protected override void OnMouseLeave(EventArgs e){hovered=false;Invalidate();base.OnMouseLeave(e);}
    protected override void OnGotFocus(EventArgs e){base.OnGotFocus(e);Invalidate();}
    protected override void OnLostFocus(EventArgs e){base.OnLostFocus(e);Invalidate();}
    protected override void OnDropDown(EventArgs e){base.OnDropDown(e);Invalidate();}
    protected override void OnDropDownClosed(EventArgs e){base.OnDropDownClosed(e);Invalidate();}
    protected override void OnSelectedIndexChanged(EventArgs e){base.OnSelectedIndexChanged(e);Invalidate();}
    protected override void OnEnabledChanged(EventArgs e){base.OnEnabledChanged(e);Invalidate();}
    private void PaintField(Graphics graphics)
    {
        using(var background=new SolidBrush(WorkspaceStyle.SurfaceColor(Parent)))graphics.FillRectangle(background,ClientRectangle);graphics.SmoothingMode=SmoothingMode.AntiAlias;
        float scale=DeviceDpi/96f;var bounds=new RectangleF(1,1,Width-2,Height-2);if(bounds.Width<=0||bounds.Height<=0)return;
        using var path=Palette.Round(bounds,Math.Min(7*scale,Height/4f));
        using var fill=new SolidBrush(Enabled?Color.White:Palette.FieldDisabled);graphics.FillPath(fill,path);
        using var border=new Pen(Focused||DroppedDown?Palette.Accent:hovered?Palette.BorderHover:Palette.InputBorder,Focused||DroppedDown?1.5f:1);graphics.DrawPath(border,path);
        int inset=(int)Math.Round(9*scale),arrow=(int)Math.Round(28*scale);
        WorkspaceStyle.DrawText(graphics,SelectedItem==null?Text:GetItemText(SelectedItem)??Text,Font,new Rectangle(inset,0,Math.Max(1,Width-inset-arrow),Height),Enabled?Palette.Ink:Palette.Muted);
        float cx=Width-15*scale,cy=Height/2f;using var pen=new Pen(Enabled?Palette.Muted:Palette.BorderHover,1.5f){StartCap=LineCap.Round,EndCap=LineCap.Round};float sign=DroppedDown?-1:1;
        graphics.DrawLines(pen,new PointF[]{new(cx-3*scale,cy-sign*1.5f*scale),new(cx,cy+sign*1.5f*scale),new(cx+3*scale,cy-sign*1.5f*scale)});
    }
    protected override void WndProc(ref Message message)
    {
        base.WndProc(ref message);
        if(DropDownStyle!=ComboBoxStyle.DropDownList)return;
        if(message.Msg==0xF&&IsHandleCreated)
        {
            using var graphics=Graphics.FromHwnd(Handle);PaintField(graphics);
        }
        else if(message.Msg is 0x317 or 0x318&&message.WParam!=0)
        {
            using var graphics=Graphics.FromHdc(message.WParam);PaintField(graphics);
        }
    }
}

internal sealed class WorkspacePagePanel:FlowLayoutPanel
{
    private bool arranging;
    public WorkspacePagePanel(){Dock=DockStyle.Fill;FlowDirection=FlowDirection.TopDown;WrapContents=false;AutoScroll=true;BackColor=Palette.Background;Margin=Padding.Empty;}
    protected override void OnLayout(LayoutEventArgs e)
    {
        if(!arranging)
        {
            arranging=true;
            try{int width=Math.Max(240,ClientSize.Width-SystemInformation.VerticalScrollBarWidth-4);foreach(Control child in Controls)Fit(child,width);}
            finally{arranging=false;}
        }
        base.OnLayout(e);
    }
    private static void Fit(Control control,int width)
    {
        if(control is RoundedCard)
        {
            control.MinimumSize=new Size(width,0);control.MaximumSize=new Size(width,0);
            foreach(Control child in control.Controls)Fit(child,width-control.Padding.Horizontal);
        }
        else if(control is FlowLayoutPanel flow)
        {
            flow.MaximumSize=new Size(width,0);
            if(flow.FlowDirection==FlowDirection.TopDown){flow.MinimumSize=new Size(width,0);flow.Width=width;foreach(Control child in flow.Controls)Fit(child,width);}
            else foreach(Control child in flow.Controls)if(child is Label)child.MaximumSize=new Size(width,0);
        }
        else if(control is Label)control.MaximumSize=new Size(width,0);
        else if(control is ComboBox or TextBox or WorkspaceTextBox)control.Width=Math.Min(control.Width,width);
    }
}

// FlowLayoutPanel retains its widest off-screen child as its scroll extent.
// The inspector instead measures each visible control against one column.
internal sealed class EditorPanel:Panel
{
    private bool arranging;
    public EditorPanel(){AutoScroll=true;DoubleBuffered=true;}
    protected override void OnLayout(LayoutEventArgs e)
    {
        base.OnLayout(e);if(arranging)return;arranging=true;
        try
        {
            int width=Math.Max(120,ClientSize.Width-Padding.Horizontal-18),y=Padding.Top+AutoScrollPosition.Y;
            foreach(Control child in Controls)
            {
                if(!child.Visible)continue;
                child.MaximumSize=new Size(width,0);
                if(child is FlowLayoutPanel flow)
                {
                    foreach(Control nested in flow.Controls)nested.MaximumSize=new Size(Math.Max(100,width-nested.Margin.Horizontal),0);
                    flow.AutoSize=false;flow.Width=width;
                    child.Size=new Size(width,flow.GetPreferredSize(new Size(width,0)).Height);
                }
                else if(child is ComboBox or ShortcutRecorder)child.Width=width;
                else if(child is TextBox or WorkspaceTextBox)child.Width=Math.Min(320,width);
                else if(child is Label){child.AutoSize=false;child.Size=child.GetPreferredSize(new Size(width,0));}
                else if(child.AutoSize)child.Size=child.GetPreferredSize(new Size(width,0));
                child.Location=new Point(Padding.Left,y);y+=child.Height+child.Margin.Bottom;
            }
            AutoScrollMinSize=new Size(0,y-AutoScrollPosition.Y+Padding.Bottom);
        }
        finally{arranging=false;}
    }
}
