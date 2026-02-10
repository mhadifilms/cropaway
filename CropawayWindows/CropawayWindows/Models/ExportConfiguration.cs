// ExportConfiguration.cs
// CropawayWindows

using System.Text.Json.Serialization;
using CommunityToolkit.Mvvm.ComponentModel;

namespace CropawayWindows.Models;

/// <summary>
/// Configuration for video export operations. Controls output codec selection,
/// alpha channel handling, and output path. Codec selection is driven by the
/// alpha channel setting: alpha requires ProRes 4444 or WebM VP9, otherwise
/// the source codec is matched where possible.
/// </summary>
public partial class ExportConfiguration : ObservableObject
{
    /// <summary>
    /// When true, preserves the original video width and adjusts height for the crop.
    /// When false, crops to the exact selected region dimensions.
    /// </summary>
    [ObservableProperty]
    private bool _preserveWidth = true;

    /// <summary>
    /// When true, exports with an alpha channel for transparency (required for
    /// circle, freehand, and AI mask modes to have transparent backgrounds).
    /// Forces ProRes 4444 or WebM VP9 codec.
    /// </summary>
    [ObservableProperty]
    private bool _enableAlphaChannel;

    /// <summary>
    /// Full path for the output file. Null if not yet specified by the user.
    /// </summary>
    [ObservableProperty]
    private string? _outputPath;

    /// <summary>
    /// Gets the output codec name based on current settings.
    /// Alpha channel requires ProRes 4444; otherwise defaults to matching the source.
    /// On Windows, uses FFmpeg codec names for the export pipeline.
    /// </summary>
    [JsonIgnore]
    public string OutputCodec
    {
        get
        {
            if (EnableAlphaChannel)
            {
                // ProRes 4444 supports alpha channel
                return "prores_ks";
            }

            // Default: will be determined by source codec at export time
            // This is a fallback; ExportService will match source codec
            return "h264_nvenc";
        }
    }

    /// <summary>
    /// Whether the export requires ProRes format (needed for alpha channel).
    /// </summary>
    [JsonIgnore]
    public bool RequiresProResExport => EnableAlphaChannel;

    /// <summary>
    /// Whether the export should attempt to match the source video's codec.
    /// </summary>
    [JsonIgnore]
    public bool ShouldMatchSourceCodec => !EnableAlphaChannel;

    /// <summary>
    /// Gets the appropriate file extension for the current export settings.
    /// ProRes uses .mov; standard codecs use .mp4.
    /// </summary>
    [JsonIgnore]
    public string OutputFileExtension => EnableAlphaChannel ? ".mov" : ".mp4";

    /// <summary>
    /// Gets the FFmpeg pixel format required for the current settings.
    /// Alpha channel requires yuva444p10le; standard uses yuv420p.
    /// </summary>
    [JsonIgnore]
    public string PixelFormat => EnableAlphaChannel ? "yuva444p10le" : "yuv420p";

    /// <summary>
    /// Gets the FFmpeg ProRes profile for alpha channel export.
    /// Profile 4 = ProRes 4444 (supports alpha).
    /// </summary>
    [JsonIgnore]
    public int ProResProfile => 4;
}
