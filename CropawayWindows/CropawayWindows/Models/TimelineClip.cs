// TimelineClip.cs
// CropawayWindows

using System.Text.Json.Serialization;
using System.Windows.Media.Imaging;
using CommunityToolkit.Mvvm.ComponentModel;

namespace CropawayWindows.Models;

/// <summary>
/// Represents a single video clip in a timeline sequence. References an existing
/// <see cref="VideoItem"/> but adds trim points (in/out) and a thumbnail strip
/// for visual representation in the timeline track.
/// </summary>
public partial class TimelineClip : ObservableObject, IEquatable<TimelineClip>
{
    /// <summary>
    /// Unique identifier for this clip instance.
    /// </summary>
    public Guid Id { get; init; } = Guid.NewGuid();

    /// <summary>
    /// Reference to the source video item. Not serialized; resolved via
    /// <see cref="VideoItemId"/> after loading from persistence.
    /// </summary>
    [ObservableProperty]
    [property: JsonIgnore]
    private VideoItem? _videoItem;

    /// <summary>
    /// ID of the source <see cref="VideoItem"/> for serialization and persistence.
    /// Used to reconnect the clip to its video after deserialization.
    /// </summary>
    public Guid VideoItemId { get; init; }

    /// <summary>
    /// In point as a normalized value (0-1) relative to the source video duration.
    /// Clamped to ensure it stays at least 0.01 before the out point.
    /// </summary>
    [ObservableProperty]
    private double _inPoint;

    /// <summary>
    /// Out point as a normalized value (0-1) relative to the source video duration.
    /// Clamped to ensure it stays at least 0.01 after the in point.
    /// </summary>
    [ObservableProperty]
    private double _outPoint = 1.0;

    /// <summary>
    /// Strip of thumbnail images for filmstrip display in the timeline track.
    /// </summary>
    [ObservableProperty]
    [property: JsonIgnore]
    private List<BitmapSource> _thumbnailStrip = [];

    public TimelineClip()
    {
    }

    public TimelineClip(VideoItem videoItem, double inPoint = 0.0, double outPoint = 1.0)
    {
        VideoItem = videoItem;
        VideoItemId = videoItem.Id;
        _inPoint = Math.Clamp(inPoint, 0.0, 1.0);
        _outPoint = Math.Clamp(outPoint, 0.0, 1.0);
    }

    // -- Clamping on property change --

    partial void OnInPointChanged(double value)
    {
        double clamped = Math.Clamp(value, 0.0, OutPoint - 0.01);
        if (Math.Abs(clamped - value) > 0.0001)
        {
            InPoint = clamped;
        }
    }

    partial void OnOutPointChanged(double value)
    {
        double clamped = Math.Clamp(value, InPoint + 0.01, 1.0);
        if (Math.Abs(clamped - value) > 0.0001)
        {
            OutPoint = clamped;
        }
    }

    // -- Computed properties --

    /// <summary>
    /// Duration of the source video in seconds.
    /// </summary>
    [JsonIgnore]
    public double SourceDuration => VideoItem?.Metadata.Duration ?? 0;

    /// <summary>
    /// Trimmed duration of this clip in seconds, based on in/out points.
    /// </summary>
    [JsonIgnore]
    public double TrimmedDuration => (OutPoint - InPoint) * SourceDuration;

    /// <summary>
    /// Start time within the source video in seconds.
    /// </summary>
    [JsonIgnore]
    public double SourceStartTime => InPoint * SourceDuration;

    /// <summary>
    /// End time within the source video in seconds.
    /// </summary>
    [JsonIgnore]
    public double SourceEndTime => OutPoint * SourceDuration;

    /// <summary>
    /// Display name for the clip, derived from the source video file name.
    /// </summary>
    [JsonIgnore]
    public string DisplayName => VideoItem?.FileName ?? "Unknown";

    /// <summary>
    /// Whether the clip has been trimmed from its original full duration.
    /// </summary>
    [JsonIgnore]
    public bool IsTrimmed => InPoint > 0.001 || OutPoint < 0.999;

    /// <summary>
    /// Crop configuration from the source video, if available.
    /// </summary>
    [JsonIgnore]
    public CropConfiguration? CropConfiguration => VideoItem?.CropConfig;

    // -- Methods --

    /// <summary>
    /// Sets the in point from an absolute time in seconds.
    /// </summary>
    public void SetInPointFromTime(double timeSeconds)
    {
        if (SourceDuration <= 0) return;
        InPoint = timeSeconds / SourceDuration;
    }

    /// <summary>
    /// Sets the out point from an absolute time in seconds.
    /// </summary>
    public void SetOutPointFromTime(double timeSeconds)
    {
        if (SourceDuration <= 0) return;
        OutPoint = timeSeconds / SourceDuration;
    }

    /// <summary>
    /// Splits this clip at a normalized position within the trimmed region (0-1).
    /// Adjusts this clip's out point and returns a new clip for the second half.
    /// Returns null if the split position is too close to either end.
    /// </summary>
    public TimelineClip? Split(double normalizedPosition)
    {
        if (VideoItem is null) return null;

        // Convert position within trimmed region to position in source
        double splitPointInSource = InPoint + normalizedPosition * (OutPoint - InPoint);

        // Validate split point has enough room on both sides
        if (splitPointInSource <= InPoint + 0.01 || splitPointInSource >= OutPoint - 0.01)
            return null;

        // Create new clip for the second half
        var newClip = new TimelineClip(VideoItem, splitPointInSource, OutPoint);

        // Adjust this clip's out point to the split point
        OutPoint = splitPointInSource;

        return newClip;
    }

    /// <summary>
    /// Creates a copy of this clip with a new unique identifier.
    /// </summary>
    public TimelineClip? Copy()
    {
        if (VideoItem is null) return null;
        return new TimelineClip(VideoItem, InPoint, OutPoint);
    }

    /// <summary>
    /// Resolves the <see cref="VideoItem"/> reference after loading from persistence.
    /// Searches the provided video list for a matching <see cref="VideoItemId"/>.
    /// </summary>
    public void ResolveVideoItem(IEnumerable<VideoItem> videos)
    {
        VideoItem = videos.FirstOrDefault(v => v.Id == VideoItemId);
    }

    public bool Equals(TimelineClip? other)
    {
        if (other is null) return false;
        if (ReferenceEquals(this, other)) return true;
        return Id == other.Id;
    }

    public override bool Equals(object? obj) => Equals(obj as TimelineClip);

    public override int GetHashCode() => Id.GetHashCode();

    public static bool operator ==(TimelineClip? left, TimelineClip? right) =>
        left is null ? right is null : left.Equals(right);

    public static bool operator !=(TimelineClip? left, TimelineClip? right) =>
        !(left == right);

    public override string ToString() =>
        $"TimelineClip({DisplayName}, {InPoint:F3}-{OutPoint:F3}, {TrimmedDuration:F2}s)";
}
