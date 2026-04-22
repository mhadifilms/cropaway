// AIPromptPoint.cs
// CropawayWindows

using System.Windows;

namespace CropawayWindows.Models;

/// <summary>
/// A point prompt for AI segmentation. Used to identify foreground (include)
/// or background (exclude) regions when performing object segmentation.
/// All coordinates are normalized to the 0-1 range relative to video dimensions.
/// </summary>
public sealed class AIPromptPoint : IEquatable<AIPromptPoint>
{
    /// <summary>
    /// Unique identifier for this prompt point.
    /// </summary>
    public Guid Id { get; init; } = Guid.NewGuid();

    /// <summary>
    /// Position in normalized 0-1 coordinates relative to the video frame.
    /// </summary>
    public Point Position { get; set; }

    /// <summary>
    /// Whether this is a positive (foreground/include) or negative (background/exclude) prompt.
    /// True = include this region in the segmentation mask.
    /// False = exclude this region from the segmentation mask.
    /// </summary>
    public bool IsPositive { get; set; }

    /// <summary>
    /// Gets the label value for the AI API. 1 for foreground (positive), 0 for background (negative).
    /// </summary>
    public int Label => IsPositive ? 1 : 0;

    public AIPromptPoint()
    {
        Position = new Point(0, 0);
        IsPositive = true;
    }

    public AIPromptPoint(Point position, bool isPositive = true)
    {
        Position = position;
        IsPositive = isPositive;
    }

    public bool Equals(AIPromptPoint? other)
    {
        if (other is null) return false;
        if (ReferenceEquals(this, other)) return true;
        return Id == other.Id;
    }

    public override bool Equals(object? obj) => Equals(obj as AIPromptPoint);

    public override int GetHashCode() => Id.GetHashCode();

    public override string ToString() =>
        $"AIPromptPoint({(IsPositive ? "+" : "-")} at {Position.X:F3},{Position.Y:F3})";
}
