// VideoMetadata.cs
// CropawayWindows

using System.Text.Json.Serialization;
using CommunityToolkit.Mvvm.ComponentModel;

namespace CropawayWindows.Models;

/// <summary>
/// Contains metadata extracted from a video file including dimensions, codec,
/// color space, and temporal properties. Populated by the video metadata
/// extraction service using FFprobe or MediaFoundation.
/// </summary>
public partial class VideoMetadata : ObservableObject
{
    // -- Dimensions --

    /// <summary>
    /// Video width in pixels.
    /// </summary>
    [ObservableProperty]
    private int _width;

    /// <summary>
    /// Video height in pixels.
    /// </summary>
    [ObservableProperty]
    private int _height;

    // -- Temporal --

    /// <summary>
    /// Video duration in seconds.
    /// </summary>
    [ObservableProperty]
    private double _duration;

    /// <summary>
    /// Video frame rate (frames per second).
    /// </summary>
    [ObservableProperty]
    private double _frameRate;

    // -- Codec and Format --

    /// <summary>
    /// Video codec type identifier (e.g., "h264", "hevc", "prores").
    /// </summary>
    [ObservableProperty]
    private string? _codecType;

    /// <summary>
    /// Whether the video contains HDR content.
    /// </summary>
    [ObservableProperty]
    private bool _isHDR;

    // -- Color Space --

    /// <summary>
    /// Color primaries (e.g., "bt709", "bt2020").
    /// </summary>
    [ObservableProperty]
    private string? _colorPrimaries;

    /// <summary>
    /// Color matrix coefficients (e.g., "bt709", "bt2020nc").
    /// </summary>
    [ObservableProperty]
    private string? _colorMatrix;

    /// <summary>
    /// Transfer function / OETF (e.g., "bt709", "smpte2084" for PQ, "arib-std-b67" for HLG).
    /// </summary>
    [ObservableProperty]
    private string? _transferFunction;

    /// <summary>
    /// Bit depth of the video (typically 8, 10, or 12).
    /// </summary>
    [ObservableProperty]
    private int _bitDepth = 8;

    /// <summary>
    /// Video bit rate in bits per second.
    /// </summary>
    [ObservableProperty]
    private long _bitRate;

    // -- Additional properties for export pipeline --

    /// <summary>
    /// Display aspect ratio (width / height).
    /// </summary>
    public double DisplayAspectRatio { get; set; } = 1.0;

    /// <summary>
    /// Nominal frame rate (from r_frame_rate).
    /// </summary>
    public double NominalFrameRate { get; set; }

    /// <summary>
    /// Human-readable codec description (e.g., "H.264/AVC").
    /// </summary>
    public string? CodecDescription { get; set; }

    /// <summary>
    /// Codec profile level.
    /// </summary>
    public string? ProfileLevel { get; set; }

    /// <summary>
    /// HDR format identifier (e.g., "HDR10", "HLG").
    /// </summary>
    public string? HDRFormat { get; set; }

    /// <summary>
    /// Audio codec name (e.g., "aac", "pcm_s16le").
    /// </summary>
    public string? AudioCodec { get; set; }

    /// <summary>
    /// Audio sample rate in Hz.
    /// </summary>
    public double? AudioSampleRate { get; set; }

    /// <summary>
    /// Number of audio channels.
    /// </summary>
    public int? AudioChannels { get; set; }

    /// <summary>
    /// Audio bit rate in bits per second.
    /// </summary>
    public long? AudioBitRate { get; set; }

    /// <summary>
    /// Whether the video contains an audio track.
    /// </summary>
    public bool HasAudio { get; set; }

    /// <summary>
    /// Container format (e.g., "mp4", "mov", "mkv").
    /// </summary>
    public string ContainerFormat { get; set; } = "mp4";

    /// <summary>
    /// Rotation angle in degrees (0, 90, 180, 270).
    /// </summary>
    public int Rotation { get; set; }

    // -- Computed display properties --

    /// <summary>
    /// Human-readable description of the color space.
    /// </summary>
    [JsonIgnore]
    public string? ColorSpaceDescription
    {
        get
        {
            if (string.IsNullOrEmpty(ColorPrimaries)) return null;

            if (ColorPrimaries.Contains("2020", StringComparison.OrdinalIgnoreCase))
                return "Rec. 2020";
            if (ColorPrimaries.Contains("709", StringComparison.OrdinalIgnoreCase))
                return "Rec. 709";
            if (ColorPrimaries.Contains("P3", StringComparison.OrdinalIgnoreCase))
                return "Display P3";

            return ColorPrimaries;
        }
    }

    /// <summary>
    /// Display string for video dimensions (e.g., "1920 x 1080").
    /// </summary>
    [JsonIgnore]
    public string DimensionsDisplay =>
        Width > 0 && Height > 0
            ? $"{Width} \u00d7 {Height}"
            : "Unknown";

    /// <summary>
    /// Display string for video duration in mm:ss or hh:mm:ss format.
    /// </summary>
    [JsonIgnore]
    public string DurationDisplay
    {
        get
        {
            if (Duration <= 0) return "0:00";

            var timeSpan = TimeSpan.FromSeconds(Duration);
            return timeSpan.TotalHours >= 1
                ? timeSpan.ToString(@"h\:mm\:ss")
                : timeSpan.ToString(@"m\:ss");
        }
    }

    /// <summary>
    /// Total number of frames in the video.
    /// </summary>
    [JsonIgnore]
    public int TotalFrameCount
    {
        get
        {
            if (Duration <= 0 || FrameRate <= 0) return 0;
            return Math.Max(1, (int)Math.Floor(Duration * FrameRate));
        }
    }

    /// <summary>
    /// Display aspect ratio.
    /// </summary>
    [JsonIgnore]
    public double AspectRatio =>
        Height > 0 ? (double)Width / Height : 1.0;

    /// <summary>
    /// Human-readable description of HDR format, if applicable.
    /// </summary>
    [JsonIgnore]
    public string? HdrDescription
    {
        get
        {
            if (!IsHDR) return null;

            if (!string.IsNullOrEmpty(TransferFunction))
            {
                if (TransferFunction.Contains("2084", StringComparison.OrdinalIgnoreCase) ||
                    TransferFunction.Contains("PQ", StringComparison.OrdinalIgnoreCase))
                    return "HDR10";
                if (TransferFunction.Contains("HLG", StringComparison.OrdinalIgnoreCase))
                    return "HLG";
            }

            return "HDR";
        }
    }

    /// <summary>
    /// Human-readable bit rate display (e.g., "25.4 Mbps", "3.2 Mbps").
    /// </summary>
    [JsonIgnore]
    public string BitRateDisplay
    {
        get
        {
            if (BitRate <= 0) return "Unknown";

            double mbps = BitRate / 1_000_000.0;
            return mbps >= 1
                ? $"{mbps:F1} Mbps"
                : $"{BitRate / 1_000.0:F0} Kbps";
        }
    }
}
