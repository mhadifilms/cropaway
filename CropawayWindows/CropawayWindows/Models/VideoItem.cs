// VideoItem.cs
// CropawayWindows

using System.Text.Json.Serialization;
using System.Windows.Media.Imaging;
using CommunityToolkit.Mvvm.ComponentModel;

namespace CropawayWindows.Models;

/// <summary>
/// Represents a single video in the project. Holds the source file path,
/// extracted metadata, thumbnail, crop configuration, and export history.
/// Implements equality by unique identifier for use in collections.
/// </summary>
public partial class VideoItem : ObservableObject, IEquatable<VideoItem>
{
    /// <summary>
    /// Unique identifier for this video item.
    /// </summary>
    public Guid Id { get; init; } = Guid.NewGuid();

    /// <summary>
    /// Full path to the source video file on disk.
    /// </summary>
    public string SourcePath { get; init; } = string.Empty;

    /// <summary>
    /// Display file name (without extension) derived from the source path.
    /// </summary>
    [ObservableProperty]
    private string _fileName = string.Empty;

    /// <summary>
    /// Date and time when this video was added to the project.
    /// </summary>
    public DateTime DateAdded { get; init; } = DateTime.Now;

    /// <summary>
    /// Thumbnail image generated from the first frame of the video.
    /// </summary>
    [ObservableProperty]
    private BitmapSource? _thumbnail;

    /// <summary>
    /// Extracted video metadata (dimensions, codec, duration, etc.).
    /// </summary>
    [ObservableProperty]
    private VideoMetadata _metadata = new();

    /// <summary>
    /// Per-video crop configuration including mode, coordinates, keyframes,
    /// and export settings.
    /// </summary>
    [ObservableProperty]
    private CropConfiguration _cropConfig = new();

    /// <summary>
    /// Path to the last exported file, if any.
    /// </summary>
    [ObservableProperty]
    private string? _lastExportPath;

    /// <summary>
    /// Date and time of the last export, if any.
    /// </summary>
    [ObservableProperty]
    private DateTime? _lastExportDate;

    /// <summary>
    /// Whether the video is currently loading metadata and thumbnail.
    /// </summary>
    [ObservableProperty]
    private bool _isLoading = true;

    /// <summary>
    /// Error message if loading failed, null if successful.
    /// </summary>
    [ObservableProperty]
    private string? _loadError;

    /// <summary>
    /// Returns true if any crop changes have been made from the default full-frame state.
    /// Delegates to the underlying <see cref="CropConfiguration.HasCropChanges"/>.
    /// </summary>
    [JsonIgnore]
    public bool HasCropChanges => CropConfig.HasCropChanges;

    public VideoItem()
    {
    }

    public VideoItem(string sourcePath)
    {
        SourcePath = sourcePath;
        _fileName = System.IO.Path.GetFileNameWithoutExtension(sourcePath);
    }

    /// <summary>
    /// Gets the file extension of the source video (e.g., ".mp4", ".mov").
    /// </summary>
    [JsonIgnore]
    public string FileExtension =>
        System.IO.Path.GetExtension(SourcePath).ToLowerInvariant();

    /// <summary>
    /// Gets the full file name with extension.
    /// </summary>
    [JsonIgnore]
    public string FullFileName =>
        System.IO.Path.GetFileName(SourcePath);

    /// <summary>
    /// Gets the parent directory of the source file.
    /// </summary>
    [JsonIgnore]
    public string? DirectoryPath =>
        System.IO.Path.GetDirectoryName(SourcePath);

    /// <summary>
    /// Gets a display string for the file size. Returns empty if file doesn't exist.
    /// </summary>
    [JsonIgnore]
    public string FileSizeDisplay
    {
        get
        {
            try
            {
                if (!System.IO.File.Exists(SourcePath)) return string.Empty;

                long bytes = new System.IO.FileInfo(SourcePath).Length;
                return bytes switch
                {
                    >= 1_073_741_824 => $"{bytes / 1_073_741_824.0:F1} GB",
                    >= 1_048_576 => $"{bytes / 1_048_576.0:F1} MB",
                    >= 1_024 => $"{bytes / 1_024.0:F0} KB",
                    _ => $"{bytes} B"
                };
            }
            catch
            {
                return string.Empty;
            }
        }
    }

    public bool Equals(VideoItem? other)
    {
        if (other is null) return false;
        if (ReferenceEquals(this, other)) return true;
        return Id == other.Id;
    }

    public override bool Equals(object? obj) => Equals(obj as VideoItem);

    public override int GetHashCode() => Id.GetHashCode();

    public static bool operator ==(VideoItem? left, VideoItem? right) =>
        left is null ? right is null : left.Equals(right);

    public static bool operator !=(VideoItem? left, VideoItem? right) =>
        !(left == right);

    public override string ToString() =>
        $"VideoItem({FileName}, {Metadata.DimensionsDisplay}, {Metadata.DurationDisplay})";
}
