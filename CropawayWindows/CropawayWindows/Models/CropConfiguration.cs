// CropConfiguration.cs
// CropawayWindows

using System.Collections.ObjectModel;
using System.Text.Json.Serialization;
using System.Windows;
using CommunityToolkit.Mvvm.ComponentModel;

namespace CropawayWindows.Models;

/// <summary>
/// Full crop state model for a single video. Stores all crop parameters across
/// all modes (rectangle, circle, freehand, AI), keyframe data, and per-video
/// export settings. All coordinates are normalized to the 0-1 range.
/// </summary>
public partial class CropConfiguration : ObservableObject
{
    // -- Mode and enabled state --

    /// <summary>
    /// The currently active crop mode.
    /// </summary>
    [ObservableProperty]
    private CropMode _mode = CropMode.Rectangle;

    /// <summary>
    /// Whether cropping is enabled for this video.
    /// </summary>
    [ObservableProperty]
    private bool _isEnabled = true;

    // -- Rectangle crop (normalized 0-1) --

    /// <summary>
    /// Normalized crop rectangle. Default is full frame (0,0,1,1).
    /// </summary>
    [ObservableProperty]
    private Rect _cropRect = new(0, 0, 1, 1);

    /// <summary>
    /// Edge-based crop insets (normalized 0-1).
    /// </summary>
    [ObservableProperty]
    private EdgeInsets _edgeInsets = EdgeInsets.Zero;

    // -- Circle crop (normalized) --

    /// <summary>
    /// Circle center in normalized coordinates. Default is center of frame (0.5, 0.5).
    /// </summary>
    [ObservableProperty]
    private Point _circleCenter = new(0.5, 0.5);

    /// <summary>
    /// Circle radius as a normalized value. Default is 0.4.
    /// </summary>
    [ObservableProperty]
    private double _circleRadius = 0.4;

    // -- Freehand mask --

    /// <summary>
    /// Serialized freehand mask path data for persistence.
    /// </summary>
    [ObservableProperty]
    private byte[]? _freehandPathData;

    /// <summary>
    /// Freehand mask points in normalized 0-1 coordinates.
    /// </summary>
    [ObservableProperty]
    private List<Point> _freehandPoints = [];

    // -- AI mask (fal.ai video tracking) --

    /// <summary>
    /// AI-generated mask data (RLE-encoded binary mask).
    /// </summary>
    [ObservableProperty]
    private byte[]? _aiMaskData;

    /// <summary>
    /// AI prompt points for object segmentation.
    /// </summary>
    [ObservableProperty]
    private List<AIPromptPoint> _aiPromptPoints = [];

    /// <summary>
    /// Text prompt for AI text-based segmentation (e.g., "person", "car").
    /// </summary>
    [ObservableProperty]
    private string? _aiTextPrompt;

    /// <summary>
    /// Unique identifier for the tracked AI object, for tracking continuity.
    /// </summary>
    [ObservableProperty]
    private string? _aiObjectId;

    /// <summary>
    /// AI-detected bounding box in normalized coordinates.
    /// </summary>
    [ObservableProperty]
    private Rect _aiBoundingBox = Rect.Empty;

    /// <summary>
    /// AI segmentation confidence score (0-1).
    /// </summary>
    [ObservableProperty]
    private double _aiConfidence;

    /// <summary>
    /// Current AI interaction mode (Point, Box, or Text).
    /// </summary>
    [ObservableProperty]
    private AIInteractionMode _aiInteractionMode = AIInteractionMode.Point;

    // -- Keyframes for animation --

    /// <summary>
    /// Ordered list of keyframes for animated crop over time.
    /// </summary>
    [ObservableProperty]
    private ObservableCollection<Keyframe> _keyframes = [];

    /// <summary>
    /// Whether keyframe-based animation is active.
    /// </summary>
    [ObservableProperty]
    private bool _keyframesEnabled;

    // -- Export settings (per-video) --

    /// <summary>
    /// When true, preserves the original video width and adjusts height for the crop.
    /// When false, crops to the exact selected region.
    /// </summary>
    [ObservableProperty]
    private bool _preserveWidth = true;

    /// <summary>
    /// When true, uses alpha channel (transparent background) for circle/freehand/AI masks.
    /// Requires ProRes 4444 or WebM VP9 export.
    /// </summary>
    [ObservableProperty]
    private bool _enableAlphaChannel;

    // -- Computed properties --

    /// <summary>
    /// Returns true if keyframe animation is enabled and there are at least two keyframes.
    /// </summary>
    [JsonIgnore]
    public bool HasKeyframes => KeyframesEnabled && Keyframes.Count > 1;

    /// <summary>
    /// Returns true if any crop changes have been made from the default full-frame state.
    /// </summary>
    [JsonIgnore]
    public bool HasCropChanges => Mode switch
    {
        CropMode.Rectangle =>
            !(CropRect.X < 0.001 && CropRect.Y < 0.001 &&
              CropRect.Width > 0.999 && CropRect.Height > 0.999) || HasKeyframes,
        CropMode.Circle => true,
        CropMode.Freehand => FreehandPoints.Count >= 3 || HasKeyframes,
        CropMode.AI => AiMaskData is not null || HasKeyframes,
        _ => false
    };

    /// <summary>
    /// Gets the effective crop rectangle for the current mode.
    /// For circle mode, returns the bounding box of the circle.
    /// For AI mode, returns the AI bounding box if available.
    /// </summary>
    [JsonIgnore]
    public Rect EffectiveCropRect => Mode switch
    {
        CropMode.Rectangle => CropRect,
        CropMode.Circle => new Rect(
            CircleCenter.X - CircleRadius,
            CircleCenter.Y - CircleRadius,
            CircleRadius * 2,
            CircleRadius * 2),
        CropMode.Freehand => CropRect,
        CropMode.AI => AiBoundingBox.Width > 0
            ? AiBoundingBox
            : new Rect(0, 0, 1, 1),
        _ => CropRect
    };

    // -- Methods --

    /// <summary>
    /// Adds a keyframe at the specified timestamp with the current crop state.
    /// Keyframes are maintained in sorted order by timestamp.
    /// If a keyframe already exists within 1ms of the timestamp, it is updated instead.
    /// </summary>
    public void AddKeyframe(double timestamp)
    {
        // Check if a keyframe already exists at this timestamp
        var existing = Keyframes.FirstOrDefault(k => Math.Abs(k.Timestamp - timestamp) < 0.001);
        if (existing is not null)
        {
            UpdateCurrentKeyframe(timestamp);
            return;
        }

        var keyframe = new Keyframe(
            timestamp,
            CropRect,
            EdgeInsets,
            CircleCenter,
            CircleRadius)
        {
            FreehandPathData = FreehandPathData is not null
                ? (byte[])FreehandPathData.Clone()
                : null
        };

        // Include AI mask data if in AI mode or if mask data exists
        if (Mode == CropMode.AI || AiMaskData is not null)
        {
            keyframe.AiMaskData = AiMaskData is not null
                ? (byte[])AiMaskData.Clone()
                : null;
            keyframe.AiPromptPoints = AiPromptPoints.Count > 0
                ? AiPromptPoints.ToList()
                : null;
            keyframe.AiBoundingBox = AiBoundingBox.Width > 0
                ? AiBoundingBox
                : null;
        }

        // Insert in sorted order by timestamp
        int insertIndex = 0;
        for (int i = 0; i < Keyframes.Count; i++)
        {
            if (Keyframes[i].Timestamp > timestamp)
            {
                insertIndex = i;
                break;
            }
            insertIndex = i + 1;
        }

        Keyframes.Insert(insertIndex, keyframe);
    }

    /// <summary>
    /// Removes the keyframe closest to the specified timestamp (within 1ms tolerance).
    /// </summary>
    public void RemoveKeyframe(double timestamp)
    {
        var toRemove = Keyframes
            .Where(k => Math.Abs(k.Timestamp - timestamp) < 0.001)
            .ToList();

        foreach (var keyframe in toRemove)
        {
            Keyframes.Remove(keyframe);
        }
    }

    /// <summary>
    /// Updates an existing keyframe at the specified timestamp with the current crop state.
    /// </summary>
    public void UpdateCurrentKeyframe(double timestamp)
    {
        var keyframe = Keyframes.FirstOrDefault(k => Math.Abs(k.Timestamp - timestamp) < 0.001);
        if (keyframe is null) return;

        keyframe.CropRect = CropRect;
        keyframe.EdgeInsets = EdgeInsets;
        keyframe.CircleCenter = CircleCenter;
        keyframe.CircleRadius = CircleRadius;
        keyframe.FreehandPathData = FreehandPathData is not null
            ? (byte[])FreehandPathData.Clone()
            : null;

        // Update AI mask data
        if (Mode == CropMode.AI || AiMaskData is not null)
        {
            keyframe.AiMaskData = AiMaskData is not null
                ? (byte[])AiMaskData.Clone()
                : null;
            keyframe.AiPromptPoints = AiPromptPoints.Count > 0
                ? AiPromptPoints.ToList()
                : null;
            keyframe.AiBoundingBox = AiBoundingBox.Width > 0
                ? AiBoundingBox
                : null;
        }
    }

    /// <summary>
    /// Resets all crop state to defaults (full frame). Does not reset
    /// preserveWidth and enableAlphaChannel as those are user preferences per video.
    /// </summary>
    public void Reset()
    {
        CropRect = new Rect(0, 0, 1, 1);
        EdgeInsets = EdgeInsets.Zero;
        CircleCenter = new Point(0.5, 0.5);
        CircleRadius = 0.4;
        FreehandPathData = null;
        FreehandPoints = [];
        AiMaskData = null;
        AiPromptPoints = [];
        AiTextPrompt = null;
        AiObjectId = null;
        AiBoundingBox = Rect.Empty;
        AiConfidence = 0;
        Keyframes = [];
        KeyframesEnabled = false;
    }

    /// <summary>
    /// Validates and clamps all crop values to their valid normalized ranges.
    /// Ensures rectangle, circle, freehand, and AI bounding box are within 0-1.
    /// </summary>
    public void ValidateAndClamp()
    {
        // Clamp rectangle to 0-1 normalized coordinates
        double rx = Math.Clamp(CropRect.X, 0, 1);
        double ry = Math.Clamp(CropRect.Y, 0, 1);
        double rw = Math.Clamp(CropRect.Width, 0.01, 1 - rx);
        double rh = Math.Clamp(CropRect.Height, 0.01, 1 - ry);
        CropRect = new Rect(rx, ry, rw, rh);

        // Clamp circle center to 0-1 and radius to valid range
        CircleCenter = new Point(
            Math.Clamp(CircleCenter.X, 0, 1),
            Math.Clamp(CircleCenter.Y, 0, 1));
        CircleRadius = Math.Clamp(CircleRadius, 0.01, 0.5);

        // Clamp freehand points to 0-1
        if (FreehandPoints.Count > 0)
        {
            FreehandPoints = FreehandPoints
                .Select(p => new Point(
                    Math.Clamp(p.X, 0, 1),
                    Math.Clamp(p.Y, 0, 1)))
                .ToList();
        }

        // Clamp AI bounding box
        if (AiBoundingBox.Width > 0)
        {
            double ax = Math.Clamp(AiBoundingBox.X, 0, 1);
            double ay = Math.Clamp(AiBoundingBox.Y, 0, 1);
            double aw = Math.Clamp(AiBoundingBox.Width, 0.01, 1 - ax);
            double ah = Math.Clamp(AiBoundingBox.Height, 0.01, 1 - ay);
            AiBoundingBox = new Rect(ax, ay, aw, ah);
        }
    }

    /// <summary>
    /// Returns true if all crop values are within valid normalized 0-1 range.
    /// </summary>
    [JsonIgnore]
    public bool IsValid
    {
        get
        {
            // Check rectangle
            bool rectValid = CropRect.X >= 0 && CropRect.X <= 1 &&
                             CropRect.Y >= 0 && CropRect.Y <= 1 &&
                             CropRect.Width > 0 && CropRect.X + CropRect.Width <= 1.001 &&
                             CropRect.Height > 0 && CropRect.Y + CropRect.Height <= 1.001;

            // Check circle
            bool circleValid = CircleCenter.X >= 0 && CircleCenter.X <= 1 &&
                               CircleCenter.Y >= 0 && CircleCenter.Y <= 1 &&
                               CircleRadius > 0 && CircleRadius <= 0.5;

            // Check freehand points
            bool freehandValid = FreehandPoints.All(p =>
                p.X >= 0 && p.X <= 1 && p.Y >= 0 && p.Y <= 1);

            return rectValid && circleValid && freehandValid;
        }
    }
}
