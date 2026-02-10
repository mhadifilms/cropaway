// EdgeInsets.cs
// CropawayWindows

using System.Text.Json.Serialization;
using System.Windows;

namespace CropawayWindows.Models;

/// <summary>
/// Represents normalized edge insets (0-1) for edge-based cropping.
/// All values are clamped to the 0-1 range on construction.
/// </summary>
public struct EdgeInsets : IEquatable<EdgeInsets>
{
    private double _top;
    private double _left;
    private double _bottom;
    private double _right;

    /// <summary>
    /// Top inset as a normalized value (0-1).
    /// </summary>
    public double Top
    {
        readonly get => _top;
        set => _top = Math.Clamp(value, 0.0, 1.0);
    }

    /// <summary>
    /// Left inset as a normalized value (0-1).
    /// </summary>
    public double Left
    {
        readonly get => _left;
        set => _left = Math.Clamp(value, 0.0, 1.0);
    }

    /// <summary>
    /// Bottom inset as a normalized value (0-1).
    /// </summary>
    public double Bottom
    {
        readonly get => _bottom;
        set => _bottom = Math.Clamp(value, 0.0, 1.0);
    }

    /// <summary>
    /// Right inset as a normalized value (0-1).
    /// </summary>
    public double Right
    {
        readonly get => _right;
        set => _right = Math.Clamp(value, 0.0, 1.0);
    }

    public EdgeInsets(double top = 0, double left = 0, double bottom = 0, double right = 0)
    {
        _top = Math.Clamp(top, 0.0, 1.0);
        _left = Math.Clamp(left, 0.0, 1.0);
        _bottom = Math.Clamp(bottom, 0.0, 1.0);
        _right = Math.Clamp(right, 0.0, 1.0);
    }

    /// <summary>
    /// Computes the normalized crop rectangle from the edge insets.
    /// Origin is at (Left, Top), size is the remaining area after insets.
    /// </summary>
    [JsonIgnore]
    public readonly Rect CropRect => new(
        Left,
        Top,
        Math.Max(0, 1.0 - Left - Right),
        Math.Max(0, 1.0 - Top - Bottom)
    );

    /// <summary>
    /// Returns true if the insets produce a valid (positive-area) crop region.
    /// </summary>
    [JsonIgnore]
    public readonly bool IsValid => Left + Right < 1.0 && Top + Bottom < 1.0;

    /// <summary>
    /// Returns a default EdgeInsets with all values set to zero (full frame).
    /// </summary>
    public static EdgeInsets Zero => new(0, 0, 0, 0);

    public readonly bool Equals(EdgeInsets other) =>
        Math.Abs(Top - other.Top) < 0.0001 &&
        Math.Abs(Left - other.Left) < 0.0001 &&
        Math.Abs(Bottom - other.Bottom) < 0.0001 &&
        Math.Abs(Right - other.Right) < 0.0001;

    public override readonly bool Equals(object? obj) =>
        obj is EdgeInsets other && Equals(other);

    public override readonly int GetHashCode() =>
        HashCode.Combine(Top, Left, Bottom, Right);

    public static bool operator ==(EdgeInsets left, EdgeInsets right) => left.Equals(right);
    public static bool operator !=(EdgeInsets left, EdgeInsets right) => !left.Equals(right);

    public override readonly string ToString() =>
        $"EdgeInsets(Top={Top:F3}, Left={Left:F3}, Bottom={Bottom:F3}, Right={Right:F3})";
}
