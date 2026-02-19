// KeyframeInterpolation.cs
// CropawayWindows

namespace CropawayWindows.Models;

/// <summary>
/// Interpolation types for transitions between keyframes.
/// Controls how crop values change over time between two keyframe positions.
/// </summary>
public enum KeyframeInterpolation
{
    /// <summary>
    /// Constant-rate interpolation between keyframes.
    /// </summary>
    Linear,

    /// <summary>
    /// Starts slow and accelerates toward the next keyframe.
    /// </summary>
    EaseIn,

    /// <summary>
    /// Starts fast and decelerates toward the next keyframe.
    /// </summary>
    EaseOut,

    /// <summary>
    /// Starts and ends slow with acceleration in the middle.
    /// </summary>
    EaseInOut,

    /// <summary>
    /// Holds the current value until the next keyframe, then snaps instantly.
    /// </summary>
    Hold
}

/// <summary>
/// Extension methods for <see cref="KeyframeInterpolation"/> providing display names.
/// </summary>
public static class KeyframeInterpolationExtensions
{
    /// <summary>
    /// Gets the human-readable display name for the interpolation type.
    /// </summary>
    public static string DisplayName(this KeyframeInterpolation interpolation) => interpolation switch
    {
        KeyframeInterpolation.Linear => "Linear",
        KeyframeInterpolation.EaseIn => "Ease In",
        KeyframeInterpolation.EaseOut => "Ease Out",
        KeyframeInterpolation.EaseInOut => "Ease In/Out",
        KeyframeInterpolation.Hold => "Hold",
        _ => interpolation.ToString()
    };

    /// <summary>
    /// Gets the Segoe Fluent Icons glyph string for the interpolation type.
    /// </summary>
    public static string IconName(this KeyframeInterpolation interpolation) => interpolation switch
    {
        KeyframeInterpolation.Linear => "\uE199",     // Line
        KeyframeInterpolation.EaseIn => "\uE110",     // Forward arrow
        KeyframeInterpolation.EaseOut => "\uE111",    // Back arrow
        KeyframeInterpolation.EaseInOut => "\uE199",  // Wave-like
        KeyframeInterpolation.Hold => "\uE15B",       // Pause / Stop
        _ => "\uE199"
    };
}
