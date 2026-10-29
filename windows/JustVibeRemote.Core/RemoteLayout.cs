namespace JustVibeRemote.Core;

public sealed record LayoutRect(double X, double Y, double Width, double Height);
public sealed record LayoutDisc(double X, double Y, double Radius);
public sealed record LayoutControl
{
    public string Id { get; init; } = "";
    public string Label { get; init; } = "";
    public string Icon { get; init; } = "label";
    public string Shape { get; init; } = "rounded";
    public LayoutRect Bounds { get; init; } = new(0,0,0,0);
    public string? Text { get; init; }
    public string? Hint { get; init; }
    public Usage? Usage { get; init; }
    public ActionKind? DefaultAction { get; init; }
}
public sealed record RemoteLayout
{
    public int Version { get; init; }
    public double Width { get; init; }
    public double Height { get; init; }
    public string BodyStyle { get; init; } = "dark";
    public string? Description { get; init; }
    public LayoutDisc? Dpad { get; init; }
    public List<LayoutControl> Buttons { get; init; } = [];
    public static readonly HashSet<string> Icons = ["power","mode","microphone","up","down","left","right","ok","home-back","home","back","menu","volume-up","volume-down","page-up","page-down","apps","label"];
    public void Validate()
    {
        static void Require(bool test) { if (!test) throw new InvalidDataException("Invalid remote layout: use unique controls with finite, in-bounds geometry and supported icons."); }
        Require(Version == 1 && double.IsFinite(Width) && double.IsFinite(Height) && Width is >= 100 and <= 2000 && Height is >= 100 and <= 2000);
        Require(BodyStyle is "silver" or "dark" && Buttons.Count is >= 1 and <= 48 && Buttons.Select(b => b.Id).Distinct().Count() == Buttons.Count && (Description?.Length ?? 0) <= 400);
        if (Dpad is { } disc) Require(double.IsFinite(disc.X) && double.IsFinite(disc.Y) && double.IsFinite(disc.Radius) && disc.Radius > 0 && disc.X - disc.Radius >= 0 && disc.Y - disc.Radius >= 0 && disc.X + disc.Radius <= Width && disc.Y + disc.Radius <= Height);
        Require(Buttons.Where(b=>b.Usage!=null).Select(b=>b.Usage).Distinct().Count()==Buttons.Count(b=>b.Usage!=null));
        foreach (var button in Buttons)
        {
            var b = button.Bounds;
            Require(System.Text.RegularExpressions.Regex.IsMatch(button.Id, @"^[a-z][a-z0-9._-]{0,47}$"));
            Require(button.Label.Length is > 0 and <= 60 && Icons.Contains(button.Icon) && button.Shape is "circle" or "pill" or "rounded" or "segment");
            Require(new[] {b.X,b.Y,b.Width,b.Height}.All(double.IsFinite) && b.X >= 0 && b.Y >= 0 && b.Width >= 16 && b.Height >= 16 && b.X+b.Width <= Width && b.Y+b.Height <= Height);
            Require((button.DefaultAction == null || Enum.IsDefined(button.DefaultAction.Value)) && (button.Text?.Length ?? 0) <= 20 && (button.Hint?.Length ?? 0) <= 300 && (button.Usage == null || button.Usage.Value.IsButton && button.Usage.Value.Page <= 65535 && button.Usage.Value.Code <= 65535));
        }
    }
    public List<Binding> Bindings(IEnumerable<Binding>? preserving = null)
    {
        var old = preserving?.ToList() ?? [];
        var used = new HashSet<int>(); var result = new List<Binding>();
        foreach (var button in Buttons)
        {
            int index = old.FindIndex(b => !used.Contains(old.IndexOf(b)) && (b.ControlID == button.Id || string.Equals(b.Name,button.Label,StringComparison.OrdinalIgnoreCase) || button.Id == "back" && b.Name == "Back"));
            if (index >= 0) { used.Add(index); result.Add(old[index] with { ControlID = button.Id, Name = button.Label }); }
            else result.Add(new Binding(button.Label,button.Usage,button.DefaultAction ?? ActionKind.Native,button.Id));
        }
        var retained=old.Where((b,i)=>!used.Contains(i)).ToList();
        if(result.Count+retained.Count>64)throw new InvalidDataException("This layout upgrade would exceed 64 controls. Existing bindings are preserved; keep stable control IDs or simplify the layout.");
        result.AddRange(retained);
        return result;
    }
    public static RemoteLayout Generic(List<Binding> bindings) => new() {
        Version = 1, Width = 240, Height = Math.Max(640,100+(bindings.Count+1)/2*80), BodyStyle = "dark",
        Description = "Generic layout. Device plugins can supply a photo-based layout.",
        Buttons = bindings.Select((b,i) => new LayoutControl { Id = b.ControlID ?? $"button-{i}", Label = b.Name, Icon = b.Action == ActionKind.Dictate ? "microphone" : "label", Text = b.Name[..Math.Min(b.Name.Length,12)], Bounds = new(25+i%2*110,70+i/2*80,80,52) }).ToList()
    };
}
