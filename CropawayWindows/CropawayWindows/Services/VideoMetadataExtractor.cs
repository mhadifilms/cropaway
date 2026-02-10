// VideoMetadataExtractor.cs
// CropawayWindows

using System.Diagnostics;
using System.Text.Json;
using CropawayWindows.Models;

namespace CropawayWindows.Services;

/// <summary>
/// Errors that can occur during metadata extraction.
/// </summary>
public class MetadataExtractionException : Exception
{
    public MetadataExtractionException(string message) : base(message) { }
    public MetadataExtractionException(string message, Exception innerException)
        : base(message, innerException) { }
}

/// <summary>
/// Extracts video metadata using ffprobe (FFmpeg's media analysis tool).
/// Parses JSON output for width, height, duration, frame rate, codec, bit depth,
/// bit rate, color info (HDR detection), and audio properties.
/// </summary>
public sealed class VideoMetadataExtractor
{
    private static readonly Lazy<VideoMetadataExtractor> _instance =
        new(() => new VideoMetadataExtractor());

    public static VideoMetadataExtractor Instance => _instance.Value;

    private VideoMetadataExtractor() { }

    /// <summary>
    /// Extracts full metadata from a video file using ffprobe.
    /// </summary>
    /// <param name="filePath">Path to the video file.</param>
    /// <returns>Populated VideoMetadata object.</returns>
    /// <exception cref="MetadataExtractionException">
    /// Thrown when ffprobe is not found or fails to parse the video.
    /// </exception>
    public async Task<VideoMetadata> ExtractMetadataAsync(string filePath)
    {
        if (!File.Exists(filePath))
            throw new MetadataExtractionException($"File not found: {filePath}");

        string? ffprobePath = FFmpegExportService.FindFFprobe();
        if (ffprobePath == null)
            throw new MetadataExtractionException(
                "ffprobe not found. Please install FFmpeg or ensure it is in your PATH.");

        string jsonOutput = await RunFFprobeAsync(ffprobePath, filePath);
        return ParseFFprobeOutput(jsonOutput, filePath);
    }

    /// <summary>
    /// Runs ffprobe with JSON output format and returns the raw output string.
    /// </summary>
    private async Task<string> RunFFprobeAsync(string ffprobePath, string filePath)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = ffprobePath,
            Arguments = $"-v quiet -print_format json -show_format -show_streams \"{filePath}\"",
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        using var process = new Process { StartInfo = startInfo };

        try
        {
            process.Start();

            // Read output and error concurrently to prevent deadlocks
            var outputTask = process.StandardOutput.ReadToEndAsync();
            var errorTask = process.StandardError.ReadToEndAsync();

            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(30));
            await process.WaitForExitAsync(cts.Token);

            string output = await outputTask;
            string error = await errorTask;

            if (process.ExitCode != 0)
            {
                throw new MetadataExtractionException(
                    $"ffprobe failed with exit code {process.ExitCode}: {error}");
            }

            if (string.IsNullOrWhiteSpace(output))
            {
                throw new MetadataExtractionException(
                    "ffprobe returned empty output. The file may be corrupt or unsupported.");
            }

            return output;
        }
        catch (OperationCanceledException)
        {
            try { process.Kill(entireProcessTree: true); } catch { }
            throw new MetadataExtractionException("ffprobe timed out after 30 seconds.");
        }
    }

    /// <summary>
    /// Parses ffprobe JSON output into a VideoMetadata object.
    /// </summary>
    private VideoMetadata ParseFFprobeOutput(string jsonOutput, string filePath)
    {
        var metadata = new VideoMetadata
        {
            ContainerFormat = Path.GetExtension(filePath).TrimStart('.').ToLowerInvariant()
        };

        JsonDocument doc;
        try
        {
            doc = JsonDocument.Parse(jsonOutput);
        }
        catch (JsonException ex)
        {
            throw new MetadataExtractionException(
                $"Failed to parse ffprobe JSON output: {ex.Message}", ex);
        }

        var root = doc.RootElement;

        // Parse format-level properties
        if (root.TryGetProperty("format", out var format))
        {
            ParseFormatInfo(format, metadata);
        }

        // Parse streams
        if (root.TryGetProperty("streams", out var streams) &&
            streams.ValueKind == JsonValueKind.Array)
        {
            foreach (var stream in streams.EnumerateArray())
            {
                string codecType = GetStringProperty(stream, "codec_type") ?? "";

                if (codecType == "video")
                {
                    ParseVideoStream(stream, metadata);
                }
                else if (codecType == "audio" && !metadata.HasAudio)
                {
                    ParseAudioStream(stream, metadata);
                }
            }
        }

        // Compute display aspect ratio
        if (metadata.Width > 0 && metadata.Height > 0)
        {
            metadata.DisplayAspectRatio = (double)metadata.Width / metadata.Height;
        }

        Debug.WriteLine($"[Metadata] {Path.GetFileName(filePath)}: " +
                        $"{metadata.Width}x{metadata.Height} @ {metadata.FrameRate:F2}fps, " +
                        $"{metadata.CodecType}, {metadata.Duration:F2}s, " +
                        $"HDR={metadata.IsHDR}, BitDepth={metadata.BitDepth}");

        return metadata;
    }

    /// <summary>
    /// Parses the "format" section of ffprobe output.
    /// </summary>
    private static void ParseFormatInfo(JsonElement format, VideoMetadata metadata)
    {
        // Duration
        if (format.TryGetProperty("duration", out var durationProp))
        {
            if (double.TryParse(durationProp.GetString(), out double duration))
                metadata.Duration = duration;
        }

        // Bit rate (format level, overridden by stream level if available)
        if (format.TryGetProperty("bit_rate", out var bitRateProp))
        {
            if (long.TryParse(bitRateProp.GetString(), out long bitRate))
                metadata.BitRate = bitRate;
        }
    }

    /// <summary>
    /// Parses a video stream from ffprobe output.
    /// Handles dimensions, frame rate, codec, bit depth, and color metadata.
    /// </summary>
    private static void ParseVideoStream(JsonElement stream, VideoMetadata metadata)
    {
        // Dimensions
        int width = GetIntProperty(stream, "width");
        int height = GetIntProperty(stream, "height");

        // Handle rotation via side_data or tags
        int rotation = 0;
        if (stream.TryGetProperty("side_data_list", out var sideData) &&
            sideData.ValueKind == JsonValueKind.Array)
        {
            foreach (var sd in sideData.EnumerateArray())
            {
                if (sd.TryGetProperty("rotation", out var rotProp))
                {
                    if (rotProp.ValueKind == JsonValueKind.Number)
                        rotation = rotProp.GetInt32();
                    else if (rotProp.ValueKind == JsonValueKind.String &&
                             int.TryParse(rotProp.GetString(), out int r))
                        rotation = r;
                }
            }
        }

        // Check tags for rotation
        if (rotation == 0 && stream.TryGetProperty("tags", out var tags))
        {
            string? rotateStr = GetStringProperty(tags, "rotate");
            if (rotateStr != null && int.TryParse(rotateStr, out int r))
                rotation = r;
        }

        metadata.Rotation = rotation;

        // Swap width/height for 90/270 degree rotations
        if (Math.Abs(rotation) == 90 || Math.Abs(rotation) == 270)
        {
            metadata.Width = height;
            metadata.Height = width;
        }
        else
        {
            metadata.Width = width;
            metadata.Height = height;
        }

        // Frame rate (r_frame_rate is the most reliable)
        string? frameRateStr = GetStringProperty(stream, "r_frame_rate");
        if (frameRateStr != null)
        {
            metadata.FrameRate = ParseFrameRate(frameRateStr);
            metadata.NominalFrameRate = metadata.FrameRate;
        }

        // Also check avg_frame_rate
        string? avgFrameRate = GetStringProperty(stream, "avg_frame_rate");
        if (avgFrameRate != null && metadata.FrameRate == 0)
        {
            metadata.FrameRate = ParseFrameRate(avgFrameRate);
        }

        // Duration (stream level overrides format level)
        if (stream.TryGetProperty("duration", out var streamDuration))
        {
            if (double.TryParse(streamDuration.GetString(), out double d) && d > 0)
                metadata.Duration = d;
        }

        // Codec
        metadata.CodecType = GetStringProperty(stream, "codec_name");
        metadata.CodecDescription = GetCodecDescription(metadata.CodecType);
        metadata.ProfileLevel = GetStringProperty(stream, "profile");

        // Bit rate (stream level)
        string? streamBitRate = GetStringProperty(stream, "bit_rate");
        if (streamBitRate != null && long.TryParse(streamBitRate, out long br) && br > 0)
            metadata.BitRate = br;

        // Bit depth
        int bitsPerRawSample = 0;
        string? bpsStr = GetStringProperty(stream, "bits_per_raw_sample");
        if (bpsStr != null && int.TryParse(bpsStr, out int bps))
            bitsPerRawSample = bps;

        if (bitsPerRawSample > 0)
        {
            metadata.BitDepth = bitsPerRawSample;
        }
        else
        {
            // Infer from pixel format
            string? pixFmt = GetStringProperty(stream, "pix_fmt");
            if (pixFmt != null)
            {
                metadata.BitDepth = InferBitDepthFromPixelFormat(pixFmt);
            }
        }

        // Color metadata
        metadata.ColorPrimaries = GetStringProperty(stream, "color_primaries");
        metadata.TransferFunction = GetStringProperty(stream, "color_transfer");
        metadata.ColorMatrix = GetStringProperty(stream, "color_space");

        // HDR detection
        bool isHDR = false;
        if (metadata.TransferFunction != null)
        {
            isHDR = metadata.TransferFunction.Contains("smpte2084") ||
                    metadata.TransferFunction.Contains("arib-std-b67");
        }
        metadata.IsHDR = isHDR;

        if (isHDR)
        {
            if (metadata.TransferFunction?.Contains("smpte2084") == true)
                metadata.HDRFormat = "HDR10";
            else if (metadata.TransferFunction?.Contains("arib-std-b67") == true)
                metadata.HDRFormat = "HLG";
        }
    }

    /// <summary>
    /// Parses an audio stream from ffprobe output.
    /// </summary>
    private static void ParseAudioStream(JsonElement stream, VideoMetadata metadata)
    {
        metadata.HasAudio = true;
        metadata.AudioCodec = GetStringProperty(stream, "codec_name");

        string? sampleRate = GetStringProperty(stream, "sample_rate");
        if (sampleRate != null && double.TryParse(sampleRate, out double sr))
            metadata.AudioSampleRate = sr;

        int channels = GetIntProperty(stream, "channels");
        if (channels > 0)
            metadata.AudioChannels = channels;

        string? audioBitRate = GetStringProperty(stream, "bit_rate");
        if (audioBitRate != null && long.TryParse(audioBitRate, out long abr))
            metadata.AudioBitRate = abr;
    }

    #region Helper Methods

    /// <summary>
    /// Parses a frame rate string like "30000/1001" or "30" to a double.
    /// </summary>
    private static double ParseFrameRate(string frameRateStr)
    {
        if (string.IsNullOrEmpty(frameRateStr))
            return 0;

        if (frameRateStr.Contains('/'))
        {
            var parts = frameRateStr.Split('/');
            if (parts.Length == 2 &&
                double.TryParse(parts[0], out double num) &&
                double.TryParse(parts[1], out double den) &&
                den > 0)
            {
                return num / den;
            }
        }

        return double.TryParse(frameRateStr, out double fps) ? fps : 0;
    }

    /// <summary>
    /// Gets a human-readable codec description from the codec name.
    /// </summary>
    private static string GetCodecDescription(string? codecName)
    {
        if (string.IsNullOrEmpty(codecName)) return "Unknown";

        return codecName.ToLowerInvariant() switch
        {
            "h264" => "H.264/AVC",
            "hevc" or "h265" => "H.265/HEVC",
            "prores" => "Apple ProRes",
            "vp9" => "VP9",
            "av1" => "AV1",
            "mpeg4" => "MPEG-4",
            "mpeg2video" => "MPEG-2",
            "mjpeg" => "Motion JPEG",
            "dnxhd" => "Avid DNxHD",
            "rawvideo" => "Raw Video",
            _ => codecName
        };
    }

    /// <summary>
    /// Infers bit depth from FFmpeg pixel format name.
    /// </summary>
    private static int InferBitDepthFromPixelFormat(string pixFmt)
    {
        if (pixFmt.Contains("16le") || pixFmt.Contains("16be"))
            return 16;
        if (pixFmt.Contains("12le") || pixFmt.Contains("12be"))
            return 12;
        if (pixFmt.Contains("10le") || pixFmt.Contains("10be") || pixFmt.Contains("p010"))
            return 10;
        return 8;
    }

    /// <summary>
    /// Safely gets a string property from a JSON element.
    /// </summary>
    private static string? GetStringProperty(JsonElement element, string name)
    {
        if (element.TryGetProperty(name, out var prop))
        {
            return prop.ValueKind switch
            {
                JsonValueKind.String => prop.GetString(),
                JsonValueKind.Number => prop.GetRawText(),
                _ => null
            };
        }
        return null;
    }

    /// <summary>
    /// Safely gets an integer property from a JSON element.
    /// </summary>
    private static int GetIntProperty(JsonElement element, string name)
    {
        if (element.TryGetProperty(name, out var prop))
        {
            if (prop.ValueKind == JsonValueKind.Number)
                return prop.GetInt32();
            if (prop.ValueKind == JsonValueKind.String &&
                int.TryParse(prop.GetString(), out int val))
                return val;
        }
        return 0;
    }

    #endregion
}
