// ZoomMode.cs
// CropawayWindows

namespace CropawayWindows.Models;

/// <summary>
/// Zoom mode for the video editor preview area.
/// </summary>
public enum ZoomMode
{
    /// <summary>
    /// Fit the video to the available window space (default behavior).
    /// </summary>
    Fit,

    /// <summary>
    /// Display the video at a specific percentage zoom level.
    /// </summary>
    Percentage
}
