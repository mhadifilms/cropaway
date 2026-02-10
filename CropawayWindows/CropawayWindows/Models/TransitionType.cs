// TransitionType.cs
// CropawayWindows

namespace CropawayWindows.Models;

/// <summary>
/// Types of transitions available between clips in a timeline sequence.
/// </summary>
public enum TransitionType
{
    /// <summary>
    /// Hard cut with no transition effect. Instant switch between clips.
    /// </summary>
    Cut,

    /// <summary>
    /// Cross-dissolve fade between the outgoing and incoming clips.
    /// </summary>
    Fade,

    /// <summary>
    /// Fades to black between clips, creating a distinct visual break.
    /// </summary>
    FadeToBlack
}

/// <summary>
/// Extension methods for <see cref="TransitionType"/> providing display names
/// and Segoe Fluent Icons glyph strings.
/// </summary>
public static class TransitionTypeExtensions
{
    /// <summary>
    /// Gets the human-readable display name for the transition type.
    /// </summary>
    public static string DisplayName(this TransitionType type) => type switch
    {
        TransitionType.Cut => "Cut",
        TransitionType.Fade => "Fade",
        TransitionType.FadeToBlack => "Fade to Black",
        _ => type.ToString()
    };

    /// <summary>
    /// Gets the Segoe Fluent Icons glyph string for the transition type.
    /// </summary>
    public static string IconName(this TransitionType type) => type switch
    {
        TransitionType.Cut => "\uE8C6",         // Cut / Scissors
        TransitionType.Fade => "\uE81E",        // Half circle / Brightness
        TransitionType.FadeToBlack => "\uE706", // Dark / Moon
        _ => "\uE8C6"
    };

    /// <summary>
    /// Whether this transition type requires a duration parameter.
    /// Cuts are instantaneous and don't need a duration.
    /// </summary>
    public static bool RequiresDuration(this TransitionType type) =>
        type != TransitionType.Cut;

    /// <summary>
    /// Gets the default duration in seconds for this transition type.
    /// </summary>
    public static double DefaultDuration(this TransitionType type) => type switch
    {
        TransitionType.Cut => 0,
        TransitionType.Fade => 0.5,
        TransitionType.FadeToBlack => 0.5,
        _ => 0
    };

    /// <summary>
    /// Gets the FFmpeg filter name used to render this transition type.
    /// </summary>
    public static string FFmpegFilterName(this TransitionType type) => type switch
    {
        TransitionType.Cut => string.Empty,
        TransitionType.Fade => "xfade=transition=fade",
        TransitionType.FadeToBlack => "xfade=transition=fadeblack",
        _ => string.Empty
    };
}
