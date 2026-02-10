// Keyframe.cs
// CropawayWindows

using System.Windows;
using CommunityToolkit.Mvvm.ComponentModel;

namespace CropawayWindows.Models;

/// <summary>
/// Represents a single keyframe in a crop animation timeline.
/// Stores the complete crop state at a specific timestamp, enabling
/// interpolation between keyframes for animated crops over time.
/// All coordinates are normalized to the 0-1 range.
/// </summary>
public partial class Keyframe : ObservableObject
{
    /// <summary>
    /// Unique identifier for this keyframe.
    /// </summary>
    public Guid Id { get; init; } = Guid.NewGuid();

    /// <summary>
    /// Timestamp in seconds within the source video where this keyframe is placed.
    /// </summary>
    [ObservableProperty]
    private double _timestamp;

    // -- Rectangle crop state --

    /// <summary>
    /// Normalized crop rectangle (0-1) at this keyframe.
    /// </summary>
    [ObservableProperty]
    private Rect _cropRect = new(0, 0, 1, 1);

    /// <summary>
    /// Edge-based crop insets at this keyframe.
    /// </summary>
    [ObservableProperty]
    private EdgeInsets _edgeInsets = EdgeInsets.Zero;

    // -- Circle crop state --

    /// <summary>
    /// Circle center in normalized coordinates at this keyframe.
    /// </summary>
    [ObservableProperty]
    private Point _circleCenter = new(0.5, 0.5);

    /// <summary>
    /// Circle radius as a normalized value at this keyframe.
    /// </summary>
    [ObservableProperty]
    private double _circleRadius = 0.4;

    // -- Freehand mask state --

    /// <summary>
    /// Serialized freehand mask path data at this keyframe.
    /// </summary>
    [ObservableProperty]
    private byte[]? _freehandPathData;

    // -- AI mask state --

    /// <summary>
    /// AI-generated mask data at this keyframe.
    /// </summary>
    [ObservableProperty]
    private byte[]? _aiMaskData;

    /// <summary>
    /// AI prompt points at this keyframe, if any.
    /// </summary>
    [ObservableProperty]
    private List<AIPromptPoint>? _aiPromptPoints;

    /// <summary>
    /// AI bounding box at this keyframe, if available.
    /// </summary>
    [ObservableProperty]
    private Rect? _aiBoundingBox;

    // -- Interpolation --

    /// <summary>
    /// Interpolation type used to transition from this keyframe to the next.
    /// </summary>
    [ObservableProperty]
    private KeyframeInterpolation _interpolation = KeyframeInterpolation.Linear;

    public Keyframe()
    {
    }

    public Keyframe(
        double timestamp,
        Rect? cropRect = null,
        EdgeInsets? edgeInsets = null,
        Point? circleCenter = null,
        double circleRadius = 0.4,
        KeyframeInterpolation interpolation = KeyframeInterpolation.Linear)
    {
        _timestamp = timestamp;
        _cropRect = cropRect ?? new Rect(0, 0, 1, 1);
        _edgeInsets = edgeInsets ?? EdgeInsets.Zero;
        _circleCenter = circleCenter ?? new Point(0.5, 0.5);
        _circleRadius = circleRadius;
        _interpolation = interpolation;
    }

    /// <summary>
    /// Creates a deep copy of this keyframe with a new unique identifier.
    /// </summary>
    public Keyframe Copy()
    {
        var copy = new Keyframe(
            Timestamp,
            CropRect,
            EdgeInsets,
            CircleCenter,
            CircleRadius,
            Interpolation)
        {
            FreehandPathData = FreehandPathData is not null
                ? (byte[])FreehandPathData.Clone()
                : null,
            AiMaskData = AiMaskData is not null
                ? (byte[])AiMaskData.Clone()
                : null,
            AiPromptPoints = AiPromptPoints?.ToList(),
            AiBoundingBox = AiBoundingBox
        };

        return copy;
    }

    public override string ToString() =>
        $"Keyframe(t={Timestamp:F3}s, rect={CropRect}, interp={Interpolation})";
}
