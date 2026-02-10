// CropMode.cs
// CropawayWindows

namespace CropawayWindows.Models;

/// <summary>
/// Available crop modes for video cropping operations.
/// </summary>
public enum CropMode
{
    Rectangle,
    Circle,
    Freehand,
    AI
}

/// <summary>
/// Extension methods for <see cref="CropMode"/> providing display names
/// and Segoe Fluent Icons glyph strings.
/// </summary>
public static class CropModeExtensions
{
    /// <summary>
    /// Gets the human-readable display name for the crop mode.
    /// </summary>
    public static string DisplayName(this CropMode mode) => mode switch
    {
        CropMode.Rectangle => "Rectangle",
        CropMode.Circle => "Circle",
        CropMode.Freehand => "Custom Mask",
        CropMode.AI => "AI Mask",
        _ => mode.ToString()
    };

    /// <summary>
    /// Gets the Segoe Fluent Icons glyph string for the crop mode.
    /// </summary>
    public static string IconName(this CropMode mode) => mode switch
    {
        CropMode.Rectangle => "\uE003",  // RectangleShape
        CropMode.Circle => "\uEA3A",     // CircleShape
        CropMode.Freehand => "\uEE56",   // Inking / Pen
        CropMode.AI => "\uE945",         // Wand / Magic
        _ => "\uE003"
    };

    /// <summary>
    /// Gets the keyboard shortcut description for the crop mode.
    /// </summary>
    public static string KeyboardShortcut(this CropMode mode) => mode switch
    {
        CropMode.Rectangle => "Ctrl+1",
        CropMode.Circle => "Ctrl+2",
        CropMode.Freehand => "Ctrl+3",
        CropMode.AI => "Ctrl+4",
        _ => string.Empty
    };
}
