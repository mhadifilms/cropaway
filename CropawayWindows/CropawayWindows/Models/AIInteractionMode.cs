// AIInteractionMode.cs
// CropawayWindows

namespace CropawayWindows.Models;

/// <summary>
/// Interaction modes for AI-based video segmentation and object tracking.
/// Determines how the user provides input to identify objects for tracking.
/// </summary>
public enum AIInteractionMode
{
    /// <summary>
    /// Click on the object to track. Positive clicks include the region,
    /// negative clicks (right-click) exclude regions.
    /// </summary>
    Point,

    /// <summary>
    /// Draw a bounding box around the object to track in the first frame.
    /// </summary>
    Box,

    /// <summary>
    /// Enter a text description of the object to track (e.g., "person", "car").
    /// </summary>
    Text
}

/// <summary>
/// Extension methods for <see cref="AIInteractionMode"/>.
/// </summary>
public static class AIInteractionModeExtensions
{
    /// <summary>
    /// Gets the human-readable display name for the interaction mode.
    /// </summary>
    public static string DisplayName(this AIInteractionMode mode) => mode switch
    {
        AIInteractionMode.Point => "Point",
        AIInteractionMode.Box => "Box",
        AIInteractionMode.Text => "Text",
        _ => mode.ToString()
    };

    /// <summary>
    /// Gets the Segoe Fluent Icons glyph string for the interaction mode.
    /// </summary>
    public static string IconName(this AIInteractionMode mode) => mode switch
    {
        AIInteractionMode.Point => "\uE1E2",  // Touch / Hand pointer
        AIInteractionMode.Box => "\uE003",    // Rectangle selection
        AIInteractionMode.Text => "\uE185",   // Text cursor
        _ => "\uE1E2"
    };

    /// <summary>
    /// Gets a user-facing description of how the interaction mode works.
    /// </summary>
    public static string Description(this AIInteractionMode mode) => mode switch
    {
        AIInteractionMode.Point => "Click on the object to track",
        AIInteractionMode.Box => "Draw a box around the object to track",
        AIInteractionMode.Text => "Enter text to describe what to select",
        _ => string.Empty
    };
}
