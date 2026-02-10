// FFmpegExportService.cs
// CropawayWindows

using System.Diagnostics;
using System.Text;
using System.Text.RegularExpressions;
using System.Windows;
using CropawayWindows.Models;

namespace CropawayWindows.Services;

/// <summary>
/// Errors that can occur during video export.
/// </summary>
public enum ExportError
{
    NoOutputPath,
    FFmpegNotFound,
    MaskGenerationFailed,
    FFmpegFailed,
    Cancelled,
    InvalidSource,
    EncoderNotAvailable
}

/// <summary>
/// Exception thrown by the FFmpeg export pipeline.
/// </summary>
public class ExportException : Exception
{
    public ExportError ErrorType { get; }
    public int? ExitCode { get; }

    public ExportException(ExportError errorType, string? message = null, int? exitCode = null)
        : base(message ?? GetDefaultMessage(errorType, exitCode))
    {
        ErrorType = errorType;
        ExitCode = exitCode;
    }

    private static string GetDefaultMessage(ExportError errorType, int? exitCode) => errorType switch
    {
        ExportError.NoOutputPath => "No output path specified.",
        ExportError.FFmpegNotFound =>
            "FFmpeg is required for video export but was not found. " +
            "Please install FFmpeg or reinstall the app.",
        ExportError.MaskGenerationFailed => "Failed to generate crop mask image.",
        ExportError.FFmpegFailed =>
            $"Video export failed (FFmpeg error code: {exitCode ?? -1}).",
        ExportError.Cancelled => "Export cancelled.",
        ExportError.InvalidSource => "Invalid source video file.",
        ExportError.EncoderNotAvailable =>
            "No compatible hardware encoder found. Falling back to software encoding.",
        _ => "An unknown export error occurred."
    };
}

/// <summary>
/// Complete FFmpeg process-based video export service.
/// Supports rectangle crop, circle mask, freehand mask, and AI mask modes
/// with hardware-accelerated encoding on NVIDIA, Intel, and AMD GPUs.
/// </summary>
public sealed class FFmpegExportService : IDisposable
{
    private Process? _ffmpegProcess;
    private CancellationTokenSource? _cancellationTokenSource;
    private readonly List<string> _tempFiles = new();
    private readonly object _lock = new();
    private bool _disposed;

    // Cached encoder detection result
    private static string? _cachedBestH264Encoder;
    private static string? _cachedBestHevcEncoder;
    private static bool _encodersCached;

    /// <summary>
    /// Cancel the current export operation.
    /// </summary>
    public void Cancel()
    {
        _cancellationTokenSource?.Cancel();

        lock (_lock)
        {
            if (_ffmpegProcess is { HasExited: false })
            {
                try { _ffmpegProcess.Kill(entireProcessTree: true); }
                catch { /* Process may have already exited */ }
            }
        }

        CleanupTempFiles();
    }

    /// <summary>
    /// Export a video with the specified crop and export configuration.
    /// </summary>
    /// <param name="sourceFilePath">Path to the source video file.</param>
    /// <param name="outputFilePath">Path for the output video file.</param>
    /// <param name="metadata">Video metadata for the source file.</param>
    /// <param name="cropMode">The crop mode to apply.</param>
    /// <param name="cropRect">Normalized crop rectangle (0-1).</param>
    /// <param name="circleCenter">Normalized circle center (0-1).</param>
    /// <param name="circleRadius">Normalized circle radius (0-1).</param>
    /// <param name="freehandPoints">Freehand mask vertices.</param>
    /// <param name="freehandPathData">Serialized bezier path data (JSON).</param>
    /// <param name="aiMaskData">AI RLE mask data.</param>
    /// <param name="aiBoundingBox">AI bounding box (normalized 0-1).</param>
    /// <param name="preserveDimensions">If true, pad output to original dimensions.</param>
    /// <param name="enableAlpha">If true, export with alpha channel (transparent background).</param>
    /// <param name="progressHandler">Callback receiving progress 0.0 to 1.0.</param>
    /// <param name="cancellationToken">Cancellation token.</param>
    /// <returns>Path to the exported video.</returns>
    public async Task<string> ExportVideoAsync(
        string sourceFilePath,
        string outputFilePath,
        VideoMetadata metadata,
        CropMode cropMode,
        Rect cropRect,
        Point circleCenter,
        double circleRadius,
        List<Point>? freehandPoints,
        byte[]? freehandPathData,
        byte[]? aiMaskData,
        Rect aiBoundingBox,
        bool preserveDimensions,
        bool enableAlpha,
        Action<double>? progressHandler = null,
        CancellationToken cancellationToken = default)
    {
        _cancellationTokenSource = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        var token = _cancellationTokenSource.Token;

        if (string.IsNullOrEmpty(outputFilePath))
            throw new ExportException(ExportError.NoOutputPath);

        var ffmpegPath = FindFFmpeg();
        if (ffmpegPath == null)
            throw new ExportException(ExportError.FFmpegNotFound);

        if (!File.Exists(sourceFilePath))
            throw new ExportException(ExportError.InvalidSource);

        // Delete existing output file
        if (File.Exists(outputFilePath))
            File.Delete(outputFilePath);

        try
        {
            // Build FFmpeg arguments
            var args = new List<string> { "-y", "-i", sourceFilePath };

            // Calculate pixel crop parameters
            int cropX = (int)(cropRect.X * metadata.Width);
            int cropY = (int)(cropRect.Y * metadata.Height);
            int cropW = (int)(cropRect.Width * metadata.Width);
            int cropH = (int)(cropRect.Height * metadata.Height);

            // Ensure even dimensions
            cropW = EnsureEven(cropW);
            cropH = EnsureEven(cropH);

            bool needsCrop = cropW != metadata.Width || cropH != metadata.Height || cropX != 0 || cropY != 0;

            switch (cropMode)
            {
                case CropMode.Rectangle:
                    if (needsCrop)
                    {
                        if (preserveDimensions)
                        {
                            string padColor = enableAlpha ? "black@0" : "black";
                            args.AddRange(new[]
                            {
                                "-vf",
                                $"crop={cropW}:{cropH}:{cropX}:{cropY}," +
                                $"pad={metadata.Width}:{metadata.Height}:{cropX}:{cropY}:color={padColor}"
                            });
                        }
                        else
                        {
                            args.AddRange(new[] { "-vf", $"crop={cropW}:{cropH}:{cropX}:{cropY}" });
                        }
                    }
                    break;

                case CropMode.Circle:
                case CropMode.Freehand:
                case CropMode.AI:
                    // Generate mask image and use it as second input
                    string maskPath = await GenerateMaskImageAsync(
                        cropMode, metadata.Width, metadata.Height,
                        cropRect, circleCenter, circleRadius,
                        freehandPoints, freehandPathData,
                        aiMaskData, token);

                    args = new List<string> { "-y", "-i", sourceFilePath, "-i", maskPath };

                    if (preserveDimensions)
                    {
                        if (enableAlpha)
                        {
                            args.AddRange(new[]
                            {
                                "-filter_complex",
                                "[1:v]format=gray[mask];[0:v][mask]alphamerge"
                            });
                        }
                        else
                        {
                            args.AddRange(new[]
                            {
                                "-filter_complex",
                                "[0:v][1:v]blend=all_mode=multiply"
                            });
                        }
                    }
                    else
                    {
                        // Crop to bounding box of the mask
                        var bbox = GetMaskBoundingBox(
                            cropMode, metadata.Width, metadata.Height,
                            cropRect, circleCenter, circleRadius,
                            freehandPoints, aiBoundingBox);

                        int bboxX = (int)bbox.X;
                        int bboxY = (int)bbox.Y;
                        int bboxW = EnsureEven((int)bbox.Width);
                        int bboxH = EnsureEven((int)bbox.Height);

                        if (enableAlpha)
                        {
                            args.AddRange(new[]
                            {
                                "-filter_complex",
                                $"[1:v]format=gray[mask];[0:v][mask]alphamerge," +
                                $"crop={bboxW}:{bboxH}:{bboxX}:{bboxY}"
                            });
                        }
                        else
                        {
                            args.AddRange(new[]
                            {
                                "-filter_complex",
                                $"[0:v][1:v]blend=all_mode=multiply," +
                                $"crop={bboxW}:{bboxH}:{bboxX}:{bboxY}"
                            });
                        }
                    }
                    break;
            }

            // Codec selection
            bool needsReencode = cropMode != CropMode.Rectangle || enableAlpha || needsCrop;

            if (!needsReencode)
            {
                args.AddRange(new[] { "-c:v", "copy" });
            }
            else
            {
                await AddVideoCodecArgs(args, metadata, enableAlpha, ffmpegPath);
            }

            // Copy audio
            args.AddRange(new[] { "-c:a", "copy" });

            // Copy global/container metadata from source
            args.AddRange(new[] { "-map_metadata", "0" });

            // Output file
            args.Add(outputFilePath);

            Debug.WriteLine($"FFmpeg: {ffmpegPath} {string.Join(" ", args)}");

            // Run FFmpeg with progress monitoring
            await RunFFmpegAsync(ffmpegPath, args, metadata.Duration, progressHandler, token);

            return outputFilePath;
        }
        finally
        {
            CleanupTempFiles();
        }
    }

    /// <summary>
    /// Calculates the output dimensions for the given crop configuration.
    /// </summary>
    public static (int Width, int Height) GetOutputDimensions(
        CropMode mode, int sourceWidth, int sourceHeight, bool preserveDimensions,
        Rect cropRect, Point circleCenter, double circleRadius,
        List<Point>? freehandPoints, Rect aiBoundingBox)
    {
        if (preserveDimensions)
            return (sourceWidth, sourceHeight);

        var bbox = GetMaskBoundingBox(
            mode, sourceWidth, sourceHeight,
            cropRect, circleCenter, circleRadius,
            freehandPoints, aiBoundingBox);

        int w = EnsureEven(Math.Max(2, (int)bbox.Width));
        int h = EnsureEven(Math.Max(2, (int)bbox.Height));
        return (w, h);
    }

    #region FFmpeg Location

    /// <summary>
    /// Searches for FFmpeg in bundled location, Program Files, and PATH.
    /// </summary>
    public static string? FindFFmpeg()
    {
        // 1. Check bundled location (next to executable)
        string? appDir = Path.GetDirectoryName(Environment.ProcessPath);
        if (appDir != null)
        {
            string bundledPath = Path.Combine(appDir, "ffmpeg.exe");
            if (File.Exists(bundledPath))
                return bundledPath;

            // Check ffmpeg subdirectory
            bundledPath = Path.Combine(appDir, "ffmpeg", "ffmpeg.exe");
            if (File.Exists(bundledPath))
                return bundledPath;
        }

        // 2. Check Program Files locations
        string[] programFilesPaths =
        {
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "ffmpeg", "bin", "ffmpeg.exe"),
            Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFilesX86), "ffmpeg", "bin", "ffmpeg.exe"),
            @"C:\ffmpeg\bin\ffmpeg.exe",
            @"C:\ffmpeg\ffmpeg.exe"
        };

        foreach (string path in programFilesPaths)
        {
            if (File.Exists(path))
                return path;
        }

        // 3. Check PATH
        string? pathEnv = Environment.GetEnvironmentVariable("PATH");
        if (pathEnv != null)
        {
            foreach (string dir in pathEnv.Split(Path.PathSeparator))
            {
                string candidate = Path.Combine(dir.Trim(), "ffmpeg.exe");
                if (File.Exists(candidate))
                    return candidate;
            }
        }

        return null;
    }

    /// <summary>
    /// Searches for ffprobe in the same locations as FFmpeg.
    /// </summary>
    public static string? FindFFprobe()
    {
        // If we know FFmpeg's location, ffprobe is likely next to it
        string? ffmpegPath = FindFFmpeg();
        if (ffmpegPath != null)
        {
            string? dir = Path.GetDirectoryName(ffmpegPath);
            if (dir != null)
            {
                string ffprobePath = Path.Combine(dir, "ffprobe.exe");
                if (File.Exists(ffprobePath))
                    return ffprobePath;
            }
        }

        // Fallback: search PATH
        string? pathEnv = Environment.GetEnvironmentVariable("PATH");
        if (pathEnv != null)
        {
            foreach (string dir in pathEnv.Split(Path.PathSeparator))
            {
                string candidate = Path.Combine(dir.Trim(), "ffprobe.exe");
                if (File.Exists(candidate))
                    return candidate;
            }
        }

        return null;
    }

    #endregion

    #region Hardware Encoder Detection

    /// <summary>
    /// Detects the best available hardware encoder for H.264.
    /// Tries NVIDIA NVENC, Intel QSV, and AMD AMF in order, falls back to libx264.
    /// </summary>
    private static async Task<string> DetectBestH264EncoderAsync(string ffmpegPath)
    {
        if (_encodersCached && _cachedBestH264Encoder != null)
            return _cachedBestH264Encoder;

        // Order: NVIDIA > Intel > AMD > Software
        string[] encoders = { "h264_nvenc", "h264_qsv", "h264_amf", "libx264" };

        foreach (string encoder in encoders)
        {
            if (await IsEncoderAvailableAsync(ffmpegPath, encoder))
            {
                _cachedBestH264Encoder = encoder;
                Debug.WriteLine($"Selected H.264 encoder: {encoder}");
                return encoder;
            }
        }

        _cachedBestH264Encoder = "libx264";
        return "libx264";
    }

    /// <summary>
    /// Detects the best available hardware encoder for HEVC.
    /// Tries NVIDIA NVENC, Intel QSV, and AMD AMF in order, falls back to libx265.
    /// </summary>
    private static async Task<string> DetectBestHevcEncoderAsync(string ffmpegPath)
    {
        if (_encodersCached && _cachedBestHevcEncoder != null)
            return _cachedBestHevcEncoder;

        string[] encoders = { "hevc_nvenc", "hevc_qsv", "hevc_amf", "libx265" };

        foreach (string encoder in encoders)
        {
            if (await IsEncoderAvailableAsync(ffmpegPath, encoder))
            {
                _cachedBestHevcEncoder = encoder;
                Debug.WriteLine($"Selected HEVC encoder: {encoder}");
                return encoder;
            }
        }

        _cachedBestHevcEncoder = "libx265";
        return "libx265";
    }

    /// <summary>
    /// Tests whether a specific encoder is available by running a quick encode test.
    /// </summary>
    private static async Task<bool> IsEncoderAvailableAsync(string ffmpegPath, string encoderName)
    {
        // Software encoders are always available
        if (encoderName == "libx264" || encoderName == "libx265")
            return true;

        try
        {
            using var process = new Process();
            process.StartInfo = new ProcessStartInfo
            {
                FileName = ffmpegPath,
                Arguments = $"-f lavfi -i nullsrc=s=256x256:d=0.1 -c:v {encoderName} -f null -",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            process.Start();

            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(10));
            try
            {
                await process.WaitForExitAsync(cts.Token);
            }
            catch (OperationCanceledException)
            {
                try { process.Kill(entireProcessTree: true); } catch { }
                return false;
            }

            return process.ExitCode == 0;
        }
        catch
        {
            return false;
        }
    }

    /// <summary>
    /// Adds the appropriate video codec arguments based on source metadata and available encoders.
    /// Preserves color metadata (HDR, BT.2020, etc.).
    /// </summary>
    private async Task AddVideoCodecArgs(
        List<string> args, VideoMetadata metadata, bool enableAlpha, string ffmpegPath)
    {
        long sourceBitrate = metadata.BitRate > 0 ? metadata.BitRate : 10_000_000;
        string targetBitrate = $"{sourceBitrate / 1000}k";

        string codec = metadata.CodecType?.ToLowerInvariant() ?? "";

        if (codec.Contains("h264") || codec.Contains("h.264") || codec.Contains("avc"))
        {
            string encoder = await DetectBestH264EncoderAsync(ffmpegPath);
            args.AddRange(new[] { "-c:v", encoder });

            // Software encoder uses CRF; hardware uses bitrate
            if (encoder == "libx264")
            {
                args.AddRange(new[] { "-crf", "18", "-preset", "medium" });
            }
            else
            {
                args.AddRange(new[] { "-b:v", targetBitrate });
            }
        }
        else if (codec.Contains("hevc") || codec.Contains("h.265") || codec.Contains("h265") ||
                 codec.StartsWith("hvc") || codec.StartsWith("hev"))
        {
            string encoder = await DetectBestHevcEncoderAsync(ffmpegPath);
            args.AddRange(new[] { "-c:v", encoder });

            if (encoder == "libx265")
            {
                args.AddRange(new[] { "-crf", "20", "-preset", "medium" });
            }
            else
            {
                args.AddRange(new[] { "-b:v", targetBitrate });
            }
        }
        else if (codec.Contains("prores") || codec.StartsWith("ap"))
        {
            // ProRes is uncommon on Windows; use high-quality H.264 as fallback
            string encoder = await DetectBestH264EncoderAsync(ffmpegPath);
            args.AddRange(new[] { "-c:v", encoder });

            if (encoder == "libx264")
            {
                args.AddRange(new[] { "-crf", "14", "-preset", "slow" });
            }
            else
            {
                // Use high bitrate for ProRes-like quality
                string highBitrate = $"{Math.Max(sourceBitrate, 50_000_000) / 1000}k";
                args.AddRange(new[] { "-b:v", highBitrate });
            }
        }
        else
        {
            // Default fallback: H.264
            string encoder = await DetectBestH264EncoderAsync(ffmpegPath);
            args.AddRange(new[] { "-c:v", encoder });

            if (encoder == "libx264")
            {
                args.AddRange(new[] { "-crf", "18", "-preset", "medium" });
            }
            else
            {
                args.AddRange(new[] { "-b:v", targetBitrate });
            }
        }

        // Pixel format
        if (enableAlpha)
        {
            args.AddRange(new[] { "-pix_fmt", "yuva420p" });
        }
        else if (metadata.BitDepth > 8 &&
                 (codec.Contains("hevc") || codec.Contains("h.265") || codec.Contains("h265")))
        {
            args.AddRange(new[] { "-pix_fmt", "yuv420p10le" });
        }

        // Preserve color metadata (HDR/SDR)
        AddColorMetadataArgs(args, metadata);

        // Mark encoders as cached
        _encodersCached = true;
    }

    /// <summary>
    /// Adds FFmpeg arguments to preserve color primaries, transfer function, and matrix.
    /// </summary>
    private static void AddColorMetadataArgs(List<string> args, VideoMetadata metadata)
    {
        // Color primaries
        if (!string.IsNullOrEmpty(metadata.ColorPrimaries))
        {
            string primaries = metadata.ColorPrimaries!;
            if (primaries.Contains("2020"))
                args.AddRange(new[] { "-color_primaries", "bt2020" });
            else if (primaries.Contains("P3"))
                args.AddRange(new[] { "-color_primaries", "smpte432" });
            else if (primaries.Contains("709"))
                args.AddRange(new[] { "-color_primaries", "bt709" });
            else if (primaries.Contains("601"))
                args.AddRange(new[] { "-color_primaries", "bt601-625" });
        }

        // Transfer function
        if (!string.IsNullOrEmpty(metadata.TransferFunction))
        {
            string transfer = metadata.TransferFunction!;
            if (transfer.Contains("2084") || transfer.Contains("PQ"))
                args.AddRange(new[] { "-color_trc", "smpte2084" });
            else if (transfer.Contains("HLG"))
                args.AddRange(new[] { "-color_trc", "arib-std-b67" });
            else if (transfer.Contains("709"))
                args.AddRange(new[] { "-color_trc", "bt709" });
        }

        // Color matrix (YCbCr)
        if (!string.IsNullOrEmpty(metadata.ColorMatrix))
        {
            string matrix = metadata.ColorMatrix!;
            if (matrix.Contains("2020"))
                args.AddRange(new[] { "-colorspace", "bt2020nc" });
            else if (matrix.Contains("709"))
                args.AddRange(new[] { "-colorspace", "bt709" });
            else if (matrix.Contains("601"))
                args.AddRange(new[] { "-colorspace", "bt601-6" });
            else if (matrix.Contains("240"))
                args.AddRange(new[] { "-colorspace", "smpte240m" });
        }
        else if (metadata.IsHDR && metadata.ColorPrimaries?.Contains("2020") == true)
        {
            args.AddRange(new[] { "-colorspace", "bt2020nc" });
        }
    }

    #endregion

    #region Filter Chains & Masks

    /// <summary>
    /// Generates a PNG mask image for circle, freehand, or AI crop modes.
    /// </summary>
    private async Task<string> GenerateMaskImageAsync(
        CropMode mode, int width, int height,
        Rect cropRect, Point circleCenter, double circleRadius,
        List<Point>? freehandPoints, byte[]? freehandPathData,
        byte[]? aiMaskData, CancellationToken token)
    {
        string maskPath = Path.Combine(Path.GetTempPath(), $"mask_{Guid.NewGuid()}.png");

        lock (_lock)
        {
            _tempFiles.Add(maskPath);
        }

        byte[] pngData = CropMaskRenderer.GenerateMaskImage(
            mode, width, height,
            cropRect, circleCenter, circleRadius,
            freehandPoints, freehandPathData, aiMaskData);

        if (pngData.Length == 0)
            throw new ExportException(ExportError.MaskGenerationFailed);

        await File.WriteAllBytesAsync(maskPath, pngData, token);
        return maskPath;
    }

    /// <summary>
    /// Computes the pixel-space bounding box of the mask for cropping.
    /// </summary>
    private static Rect GetMaskBoundingBox(
        CropMode mode, int width, int height,
        Rect cropRect, Point circleCenter, double circleRadius,
        List<Point>? freehandPoints, Rect aiBoundingBox)
    {
        switch (mode)
        {
            case CropMode.Rectangle:
                return new Rect(
                    cropRect.X * width,
                    cropRect.Y * height,
                    cropRect.Width * width,
                    cropRect.Height * height);

            case CropMode.Circle:
            {
                double cx = circleCenter.X * width;
                double cy = circleCenter.Y * height;
                double r = circleRadius * Math.Min(width, height);
                return new Rect(cx - r, cy - r, r * 2, r * 2);
            }

            case CropMode.Freehand:
            {
                if (freehandPoints == null || freehandPoints.Count == 0)
                    return new Rect(0, 0, width, height);

                double minX = double.MaxValue, minY = double.MaxValue;
                double maxX = double.MinValue, maxY = double.MinValue;

                foreach (var pt in freehandPoints)
                {
                    double px = pt.X * width;
                    double py = pt.Y * height;
                    if (px < minX) minX = px;
                    if (py < minY) minY = py;
                    if (px > maxX) maxX = px;
                    if (py > maxY) maxY = py;
                }

                return new Rect(minX, minY, maxX - minX, maxY - minY);
            }

            case CropMode.AI:
            {
                if (aiBoundingBox.Width > 0)
                {
                    return new Rect(
                        aiBoundingBox.X * width,
                        aiBoundingBox.Y * height,
                        aiBoundingBox.Width * width,
                        aiBoundingBox.Height * height);
                }
                return new Rect(0, 0, width, height);
            }

            default:
                return new Rect(0, 0, width, height);
        }
    }

    #endregion

    #region FFmpeg Process Execution

    /// <summary>
    /// Runs the FFmpeg process with progress monitoring from stdout and stderr.
    /// </summary>
    private async Task RunFFmpegAsync(
        string ffmpegPath, List<string> arguments, double duration,
        Action<double>? progressHandler, CancellationToken token)
    {
        // Prepend -progress pipe:1 for structured progress output
        var fullArgs = new List<string> { "-progress", "pipe:1" };
        fullArgs.AddRange(arguments);

        var startInfo = new ProcessStartInfo
        {
            FileName = ffmpegPath,
            Arguments = string.Join(" ", fullArgs.Select(EscapeArgument)),
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        using var process = new Process { StartInfo = startInfo };
        var stderrBuilder = new StringBuilder();

        lock (_lock)
        {
            _ffmpegProcess = process;
        }

        try
        {
            process.Start();

            double lastProgress = 0;

            // Read stdout and stderr concurrently
            var stdoutTask = Task.Run(async () =>
            {
                using var reader = process.StandardOutput;
                string? line;
                while ((line = await reader.ReadLineAsync(token)) != null)
                {
                    if (token.IsCancellationRequested) break;

                    // Parse "out_time_ms=12345678"
                    if (line.StartsWith("out_time_ms="))
                    {
                        string msStr = line["out_time_ms=".Length..];
                        if (long.TryParse(msStr, out long ms) && duration > 0)
                        {
                            double seconds = ms / 1_000_000.0;
                            double progress = Math.Min(0.99, seconds / duration);
                            if (progress > lastProgress)
                            {
                                lastProgress = progress;
                                progressHandler?.Invoke(progress);
                            }
                        }
                    }
                    // Parse "out_time=00:00:01.234"
                    else if (line.StartsWith("out_time="))
                    {
                        string timeStr = line["out_time=".Length..];
                        if (TryParseFFmpegTime(timeStr, out double time) && duration > 0)
                        {
                            double progress = Math.Min(0.99, time / duration);
                            if (progress > lastProgress)
                            {
                                lastProgress = progress;
                                progressHandler?.Invoke(progress);
                            }
                        }
                    }
                }
            }, token);

            var stderrTask = Task.Run(async () =>
            {
                using var reader = process.StandardError;
                string? line;
                while ((line = await reader.ReadLineAsync(token)) != null)
                {
                    stderrBuilder.AppendLine(line);

                    // Fallback progress: "time=00:00:01.23"
                    if (lastProgress == 0 && duration > 0)
                    {
                        var match = Regex.Match(line, @"time=(\d+:\d+:\d+\.\d+)");
                        if (match.Success && TryParseFFmpegTime(match.Groups[1].Value, out double time))
                        {
                            double progress = Math.Min(0.99, time / duration);
                            if (progress > lastProgress)
                            {
                                lastProgress = progress;
                                progressHandler?.Invoke(progress);
                            }
                        }
                    }
                }
            }, token);

            await process.WaitForExitAsync(token);

            // Wait for output reading to complete
            try
            {
                await Task.WhenAll(stdoutTask, stderrTask).WaitAsync(TimeSpan.FromSeconds(5));
            }
            catch { /* Timeout reading remaining output is acceptable */ }

            if (token.IsCancellationRequested)
                throw new ExportException(ExportError.Cancelled);

            if (process.ExitCode != 0)
            {
                Debug.WriteLine($"FFmpeg stderr: {stderrBuilder}");
                throw new ExportException(ExportError.FFmpegFailed,
                    $"Video export failed (FFmpeg error code: {process.ExitCode}). " +
                    $"Details: {stderrBuilder.ToString().TakeLast(500)}",
                    process.ExitCode);
            }

            // Report 100% on success
            progressHandler?.Invoke(1.0);
        }
        finally
        {
            lock (_lock)
            {
                _ffmpegProcess = null;
            }
        }
    }

    /// <summary>
    /// Parses an FFmpeg time string "HH:MM:SS.mmm" to seconds.
    /// </summary>
    private static bool TryParseFFmpegTime(string timeStr, out double seconds)
    {
        seconds = 0;
        var parts = timeStr.Split(':');
        if (parts.Length != 3) return false;

        if (double.TryParse(parts[0], out double h) &&
            double.TryParse(parts[1], out double m) &&
            double.TryParse(parts[2], out double s))
        {
            seconds = h * 3600 + m * 60 + s;
            return true;
        }

        return false;
    }

    /// <summary>
    /// Escapes an FFmpeg argument for command-line usage.
    /// </summary>
    private static string EscapeArgument(string arg)
    {
        if (arg.Contains(' ') || arg.Contains('"'))
            return $"\"{arg.Replace("\"", "\\\"")}\"";
        return arg;
    }

    #endregion

    #region Helpers

    /// <summary>
    /// Ensures a dimension value is even (required by FFmpeg).
    /// </summary>
    public static int EnsureEven(int value)
    {
        return value % 2 == 0 ? value : Math.Max(2, value - 1);
    }

    private void CleanupTempFiles()
    {
        lock (_lock)
        {
            foreach (string path in _tempFiles)
            {
                try { if (File.Exists(path)) File.Delete(path); }
                catch { /* Best effort cleanup */ }
            }
            _tempFiles.Clear();
        }
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        Cancel();
        _cancellationTokenSource?.Dispose();
    }

    #endregion
}
