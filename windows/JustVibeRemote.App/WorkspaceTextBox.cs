using System.ComponentModel;
using System.Diagnostics.CodeAnalysis;
using System.Drawing.Drawing2D;

namespace JustVibeRemote;

// Keep the Windows edit control for caret, selection, clipboard, IME and UIA.
// Only its surrounding surface and insets are authored here.
internal class WorkspaceTextBox:UserControl
{
    private readonly PaddedEdit edit=new(){BorderStyle=BorderStyle.None,BackColor=Color.White,ForeColor=Palette.Ink,TabStop=true};
    private bool hovered;
    public WorkspaceTextBox()
    {
        AutoSize=false;Size=new Size(320,38);MinimumSize=new Size(80,36);Margin=new Padding(0,0,0,12);BackColor=Color.White;Font=WorkspaceStyle.Text();TabStop=false;
        SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer,true);
        Controls.Add(edit);edit.CommandKey=ProcessEditCommand;
        edit.TextChanged+=(_,e)=>OnTextChanged(e);edit.KeyDown+=(_,e)=>OnKeyDown(e);edit.KeyUp+=(_,e)=>OnKeyUp(e);edit.DoubleClick+=(_,e)=>OnDoubleClick(e);
        edit.GotFocus+=(_,_)=>Invalidate();edit.LostFocus+=(_,_)=>Invalidate();
        MouseEnter+=(_,_)=>SetHover(true);MouseLeave+=(_,_)=>SetHover(false);edit.MouseEnter+=(_,_)=>SetHover(true);edit.MouseLeave+=(_,_)=>SetHover(false);
    }
    [AllowNull]
    public override string Text { get=>edit?.Text??"";set{if(edit!=null)edit.Text=value??"";} }
    [DefaultValue("")]
    public string PlaceholderText { get=>edit.PlaceholderText;set=>edit.PlaceholderText=value; }
    [DefaultValue(false)]
    public bool ReadOnly { get=>edit.ReadOnly;set{edit.ReadOnly=value;Invalidate();} }
    internal bool NativeReadOnly=>edit.ReadOnly;
    internal void SelectAll()=>edit.SelectAll();
    internal void PreviewDoubleClick()=>edit.PreviewDoubleClick();
    internal KeyEventArgs PreviewKey(Keys keys){var args=new KeyEventArgs(keys);edit.PreviewKey(args);return args;}
    protected virtual bool ProcessEditCommand(Keys keys)=>false;
    protected virtual int EditRightInset=>0;
    protected Rectangle FieldBounds=>new(0,0,Math.Max(1,Width-EditRightInset),Height);
    protected void FocusEdit()=>edit.Focus();
    internal bool PreviewCommand(Keys keys)=>edit.PreviewCommand(keys);
    private void SetHover(bool value){hovered=value;Invalidate();}
    protected override void OnFontChanged(EventArgs e){base.OnFontChanged(e);if(edit!=null){edit.Font=Font;PerformLayout();}}
    protected override void OnEnabledChanged(EventArgs e){base.OnEnabledChanged(e);edit.BackColor=Enabled?Color.White:Palette.FieldDisabled;Invalidate();}
    protected override void OnEnter(EventArgs e){base.OnEnter(e);if(!edit.Focused)edit.Focus();Invalidate();}
    protected override void OnLayout(LayoutEventArgs e)
    {
        base.OnLayout(e);if(edit==null)return;int inset=(int)Math.Round(12*DeviceDpi/96f);
        edit.Bounds=new Rectangle(inset,Math.Max(2,(Height-edit.PreferredHeight)/2),Math.Max(1,Width-2*inset-EditRightInset),edit.PreferredHeight);
        edit.AccessibleName=AccessibleName??PlaceholderText;
    }
    protected override void OnPaintBackground(PaintEventArgs e)=>WorkspaceStyle.FillBackground(e.Graphics,WorkspaceStyle.SurfaceColor(Parent),ClientRectangle);
    protected override void OnPaint(PaintEventArgs e)
    {
        e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;float scale=DeviceDpi/96f;
        using var shape=Palette.Round(new RectangleF(1,1,FieldBounds.Width-2,Height-2),7*scale);
        using var fill=new SolidBrush(Enabled?Color.White:Palette.FieldDisabled);e.Graphics.FillPath(fill,shape);
        using var border=new Pen(edit.Focused?Palette.Accent:hovered?Palette.BorderHover:Palette.InputBorder,edit.Focused?1.6f:1);e.Graphics.DrawPath(border,shape);
    }
    private sealed class PaddedEdit:TextBox
    {
        internal Func<Keys,bool>? CommandKey;
        protected override bool ProcessCmdKey(ref Message message,Keys keyData)=>CommandKey?.Invoke(keyData)==true||base.ProcessCmdKey(ref message,keyData);
        internal bool PreviewCommand(Keys keys){var message=Message.Create(Handle,0x100,(IntPtr)(keys&Keys.KeyCode),IntPtr.Zero);return ProcessCmdKey(ref message,keys);}
        internal void PreviewDoubleClick()=>OnDoubleClick(EventArgs.Empty);
        internal void PreviewKey(KeyEventArgs args)=>OnKeyDown(args);
        protected override void WndProc(ref Message message)
        {
            base.WndProc(ref message);
            if(message.Msg is 0x317 or 0x318&&message.WParam!=0&&Text.Length==0&&PlaceholderText.Length>0&&!Focused)
            {
                using var graphics=Graphics.FromHdc(message.WParam);WorkspaceStyle.DrawText(graphics,PlaceholderText,Font,ClientRectangle,Palette.Muted);
            }
        }
    }
}
