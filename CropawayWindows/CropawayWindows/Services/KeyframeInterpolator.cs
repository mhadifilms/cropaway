// KeyframeInterpolator.cs
// CropawayWindows

using System.Windows;
using CropawayWindows.Models;

namespace CropawayWindows.Services;

/// <summary>
/// Represents the fully interpolated crop state at a specific point in time.
/// Contains all crop parameters for every mode, allowing seamless transitions.
/// </summary>
public struct InterpolatedCropState
{
    /// <summary>Normalized crop rectangle (0-1).</summary>
    public Rect CropRect { get; set; }

    /// <summary>Normalized edge insets.</summary>
    public EdgeInsets EdgeInsets { get; set; }

    /// <summary>Normalized circle center (0-1).</summary>
    public Point CircleCenter { get; set; }

    /// <summary>Normalized circle radius (relative to min dimension).</summary>
    public double CircleRadius { get; set; }

    /// <summary>Freehand mask polygon points (normalized 0-1).</summary>
    public List<Point> FreehandPoints { get; set; }

    /// <summary>Serialized bezier path data for freehand mask (JSON).</summary>
    public byte[]? FreehandPathData { get; set; }

    /// <summary>AI RLE mask data for pixel-perfect segmentation.</summary>
    public byte[]? AIMaskData { get; set; }

    /// <summary>AI bounding box in normalized coordinates (0-1).</summary>
    public Rect AIBoundingBox { get; set; }
}

/// <summary>
/// Represents a keyframe's crop state for interpolation.
/// This is the data that gets interpolated between keyframes.
/// </summary>
public class KeyframeData
{
    public double Timestamp { get; set; }
    public Rect CropRect { get; set; }
    public EdgeInsets EdgeInsets { get; set; }
    public Point CircleCenter { get; set; }
    public double CircleRadius { get; set; }
    public List<Point> FreehandPoints { get; set; } = new();
    public byte[]? FreehandPathData { get; set; }
    public byte[]? AIMaskData { get; set; }
    public Rect? AIBoundingBox { get; set; }
    public KeyframeInterpolation Interpolation { get; set; } = KeyframeInterpolation.Linear;
}

/// <summary>
/// Singleton service that interpolates between keyframes over time.
/// Supports linear, ease-in, ease-out, ease-in-out, and hold easing functions.
/// All coordinates remain in normalized 0-1 space.
/// </summary>
public sealed class KeyframeInterpolator
{
    private static readonly Lazy<KeyframeInterpolator> _instance =
        new(() => new KeyframeInterpolator());

    /// <summary>Singleton instance.</summary>
    public static KeyframeInterpolator Instance => _instance.Value;

    private KeyframeInterpolator() { }

    /// <summary>
    /// Interpolates between keyframes at the given timestamp.
    /// </summary>
    /// <param name="keyframes">List of keyframes sorted by timestamp.</param>
    /// <param name="timestamp">Current time in seconds.</param>
    /// <param name="mode">Current crop mode (affects AI bounding box usage).</param>
    /// <returns>Interpolated crop state at the given time.</returns>
    public InterpolatedCropState Interpolate(
        IReadOnlyList<KeyframeData> keyframes,
        double timestamp,
        CropMode mode)
    {
        if (keyframes.Count == 0)
            return DefaultState();

        // Ensure sorted order
        var sorted = keyframes.OrderBy(k => k.Timestamp).ToList();

        // Before first keyframe: use first keyframe's state
        if (timestamp <= sorted[0].Timestamp)
            return StateFromKeyframe(sorted[0], mode);

        // After last keyframe: use last keyframe's state
        if (timestamp >= sorted[^1].Timestamp)
            return StateFromKeyframe(sorted[^1], mode);

        // Find the surrounding keyframes
        int nextIndex = sorted.FindIndex(k => k.Timestamp > timestamp);
        if (nextIndex < 0)
            return StateFromKeyframe(sorted[^1], mode);

        var prev = sorted[nextIndex - 1];
        var next = sorted[nextIndex];

        // Calculate interpolation factor
        double duration = next.Timestamp - prev.Timestamp;
        if (duration <= 0)
            return StateFromKeyframe(prev, mode);

        double elapsed = timestamp - prev.Timestamp;
        double rawT = elapsed / duration;

        // Apply easing based on previous keyframe's interpolation type
        double t = ApplyEasing(rawT, prev.Interpolation);

        // Interpolate between the two states
        return InterpolateStates(
            StateFromKeyframe(prev, mode),
            StateFromKeyframe(next, mode),
            t);
    }

    /// <summary>
    /// Returns the default crop state (near-full frame).
    /// </summary>
    private static InterpolatedCropState DefaultState() => new()
    {
        CropRect = new Rect(0.1, 0.1, 0.8, 0.8),
        EdgeInsets = new EdgeInsets(),
        CircleCenter = new Point(0.5, 0.5),
        CircleRadius = 0.4,
        FreehandPoints = new List<Point>(),
        FreehandPathData = null,
        AIMaskData = null,
        AIBoundingBox = Rect.Empty
    };

    /// <summary>
    /// Converts a keyframe to an InterpolatedCropState.
    /// In AI mode, uses the AI bounding box as the effective crop rect when present.
    /// </summary>
    private static InterpolatedCropState StateFromKeyframe(KeyframeData keyframe, CropMode mode)
    {
        // In AI mode, use aiBoundingBox as the effective crop rect when present
        Rect effectiveCropRect;
        if (mode == CropMode.AI && keyframe.AIBoundingBox.HasValue &&
            keyframe.AIBoundingBox.Value.Width > 0)
        {
            effectiveCropRect = keyframe.AIBoundingBox.Value;
        }
        else
        {
            effectiveCropRect = keyframe.CropRect;
        }

        return new InterpolatedCropState
        {
            CropRect = effectiveCropRect,
            EdgeInsets = keyframe.EdgeInsets,
            CircleCenter = keyframe.CircleCenter,
            CircleRadius = keyframe.CircleRadius,
            FreehandPoints = keyframe.FreehandPoints,
            FreehandPathData = keyframe.FreehandPathData,
            AIMaskData = keyframe.AIMaskData,
            AIBoundingBox = keyframe.AIBoundingBox ?? Rect.Empty
        };
    }

    #region Easing Functions

    /// <summary>
    /// Applies the easing function to a raw interpolation factor (0-1).
    /// </summary>
    public static double ApplyEasing(double t, KeyframeInterpolation interpolation)
    {
        return interpolation switch
        {
            KeyframeInterpolation.Linear => t,
            KeyframeInterpolation.EaseIn => t * t,
            KeyframeInterpolation.EaseOut => 1.0 - (1.0 - t) * (1.0 - t),
            KeyframeInterpolation.EaseInOut => t < 0.5
                ? 2.0 * t * t
                : 1.0 - Math.Pow(-2.0 * t + 2.0, 2) / 2.0,
            KeyframeInterpolation.Hold => 0.0, // Always return start value
            _ => t
        };
    }

    #endregion

    #region Interpolation Helpers

    /// <summary>
    /// Interpolates between two full crop states.
    /// Freehand and AI mask data use "hold" interpolation (snap at midpoint).
    /// </summary>
    private static InterpolatedCropState InterpolateStates(
        InterpolatedCropState from,
        InterpolatedCropState to,
        double t)
    {
        return new InterpolatedCropState
        {
            CropRect = Lerp(from.CropRect, to.CropRect, t),
            EdgeInsets = LerpEdgeInsets(from.EdgeInsets, to.EdgeInsets, t),
            CircleCenter = Lerp(from.CircleCenter, to.CircleCenter, t),
            CircleRadius = Lerp(from.CircleRadius, to.CircleRadius, t),
            // Freehand: hold interpolation (snap at midpoint)
            FreehandPoints = t < 0.5 ? from.FreehandPoints : to.FreehandPoints,
            FreehandPathData = t < 0.5 ? from.FreehandPathData : to.FreehandPathData,
            // AI masks: hold interpolation (snap at midpoint)
            AIMaskData = t < 0.5 ? from.AIMaskData : to.AIMaskData,
            // AI bounding box: linear interpolation
            AIBoundingBox = Lerp(from.AIBoundingBox, to.AIBoundingBox, t)
        };
    }

    /// <summary>Linearly interpolates between two double values.</summary>
    public static double Lerp(double a, double b, double t)
    {
        return a + (b - a) * t;
    }

    /// <summary>Linearly interpolates between two points.</summary>
    public static Point Lerp(Point a, Point b, double t)
    {
        return new Point(
            Lerp(a.X, b.X, t),
            Lerp(a.Y, b.Y, t));
    }

    /// <summary>Linearly interpolates between two rectangles.</summary>
    public static Rect Lerp(Rect a, Rect b, double t)
    {
        // Handle empty rects
        if (a.IsEmpty && b.IsEmpty) return Rect.Empty;
        if (a.IsEmpty) a = new Rect(0, 0, 0, 0);
        if (b.IsEmpty) b = new Rect(0, 0, 0, 0);

        return new Rect(
            Lerp(a.X, b.X, t),
            Lerp(a.Y, b.Y, t),
            Lerp(a.Width, b.Width, t),
            Lerp(a.Height, b.Height, t));
    }

    /// <summary>Linearly interpolates between two edge insets.</summary>
    private static EdgeInsets LerpEdgeInsets(EdgeInsets a, EdgeInsets b, double t)
    {
        return new EdgeInsets(
            top: Lerp(a.Top, b.Top, t),
            left: Lerp(a.Left, b.Left, t),
            bottom: Lerp(a.Bottom, b.Bottom, t),
            right: Lerp(a.Right, b.Right, t));
    }

    #endregion
}
