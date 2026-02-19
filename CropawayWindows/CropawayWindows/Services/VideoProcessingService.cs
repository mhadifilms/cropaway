// VideoProcessingService.cs
// CropawayWindows

using System.Diagnostics;
using System.IO;
using System.Text;
using System.Windows;
using CropawayWindows.Models;

namespace CropawayWindows.Services;

/// <summary>
/// Handles video export with keyframe animation support.
/// Wraps FFmpegExportService for single-frame exports and adds
/// keyframe interpolation for animated crop exports.
/// </summary>
public sealed class VideoProcessingService : IDisposable
{
    private readonly FFmpegExportService _exportService = new();
    private CancellationTokenSource? _cts;
    private readonly List<string> _tempFiles = new();
    private bool _disposed;

    public void Cancel()
    {
        _cts?.Cancel();
        _exportService.Cancel();
        CleanupTempFiles();
    }

    /// <summary>
    /// Export a video with optional keyframe animation.
    /// If keyframes exist and are enabled, uses segmented export with per-segment crops.
    /// Otherwise, delegates to FFmpegExportService for single-crop export.
    /// </summary>
    public async Task<string> ExportWithKeyframesAsync(
        VideoItem video,
        string outputPath,
        Action<double>? progressHandler = null,
        CancellationToken cancellationToken = default)
    {
        _cts = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        var token = _cts.Token;

        var config = video.CropConfig;
        var metadata = video.Metadata;

        // If no keyframes, delegate to simple export
        if (!config.HasKeyframes)
        {
            return await _exportService.ExportVideoAsync(
                video.SourcePath,
                outputPath,
                metadata,
                config.Mode,
                config.CropRect,
                config.CircleCenter,
                config.CircleRadius,
                config.FreehandPoints.Count > 0 ? config.FreehandPoints : null,
                config.FreehandPathData,
                config.AiMaskData,
                config.AiBoundingBox,
                config.PreserveWidth,
                config.EnableAlphaChannel,
                progressHandler,
                token);
        }

        // Keyframed export
        if (config.Mode == CropMode.Rectangle)
        {
            return await ExportRectangleKeyframedAsync(
                video, outputPath, progressHandler, token);
        }
        else
        {
            return await ExportMaskedKeyframedAsync(
                video, outputPath, progressHandler, token);
        }
    }

    /// <summary>
    /// Rectangle keyframed export using FFmpeg crop filter with time expressions.
    /// </summary>
    private async Task<string> ExportRectangleKeyframedAsync(
        VideoItem video, string outputPath,
        Action<double>? progressHandler, CancellationToken token)
    {
        var config = video.CropConfig;
        var metadata = video.Metadata;
        var keyframes = config.Keyframes.OrderBy(kf => kf.Timestamp).ToList();

        if (keyframes.Count < 2)
        {
            // Fallback to single crop
            return await _exportService.ExportVideoAsync(
                video.SourcePath, outputPath, metadata,
                config.Mode, config.CropRect, config.CircleCenter, config.CircleRadius,
                null, null, null, Rect.Empty,
                config.PreserveWidth, config.EnableAlphaChannel,
                progressHandler, token);
        }

        var ffmpegPath = FFmpegExportService.FindFFmpeg();
        if (ffmpegPath == null)
            throw new ExportException(ExportError.FFmpegNotFound);

        // Build time-based crop expressions
        string xExpr = BuildPiecewiseLinearExpr(keyframes, kf => kf.CropRect.X * metadata.Width);
        string yExpr = BuildPiecewiseLinearExpr(keyframes, kf => kf.CropRect.Y * metadata.Height);
        string wExpr = BuildPiecewiseLinearExpr(keyframes, kf => kf.CropRect.Width * metadata.Width);
        string hExpr = BuildPiecewiseLinearExpr(keyframes, kf => kf.CropRect.Height * metadata.Height);

        // Ensure even dimensions using ceil/floor
        string cropFilter = $"crop='{EvenExpr(wExpr)}:{EvenExpr(hExpr)}:{xExpr}:{yExpr}'";

        if (config.PreserveWidth)
        {
            string padColor = config.EnableAlphaChannel ? "black@0" : "black";
            cropFilter += $",pad={metadata.Width}:{metadata.Height}:(ow-iw)/2:(oh-ih)/2:color={padColor}";
        }

        var args = new List<string>
        {
            "-y", "-progress", "pipe:1",
            "-i", video.SourcePath,
            "-vf", cropFilter
        };

        // Add codec args (use H.264 with hardware acceleration)
        await AddCodecArgs(args, metadata, config.EnableAlphaChannel, ffmpegPath);
        args.AddRange(new[] { "-c:a", "copy", "-map_metadata", "0", outputPath });

        await RunFFmpegWithProgressAsync(ffmpegPath, args, metadata.Duration, progressHandler, token);
        return outputPath;
    }

    /// <summary>
    /// Masked mode keyframed export: segments video, generates masks per segment, concatenates.
    /// </summary>
    private async Task<string> ExportMaskedKeyframedAsync(
        VideoItem video, string outputPath,
        Action<double>? progressHandler, CancellationToken token)
    {
        var config = video.CropConfig;
        var metadata = video.Metadata;
        var keyframes = config.Keyframes.OrderBy(kf => kf.Timestamp).ToList();

        if (keyframes.Count < 2)
        {
            return await _exportService.ExportVideoAsync(
                video.SourcePath, outputPath, metadata,
                config.Mode, config.CropRect, config.CircleCenter, config.CircleRadius,
                config.FreehandPoints.Count > 0 ? config.FreehandPoints : null,
                config.FreehandPathData, config.AiMaskData, config.AiBoundingBox,
                config.PreserveWidth, config.EnableAlphaChannel,
                progressHandler, token);
        }

        // Export each segment between keyframes
        var segmentPaths = new List<string>();
        int totalSegments = keyframes.Count - 1;

        for (int i = 0; i < totalSegments; i++)
        {
            token.ThrowIfCancellationRequested();

            var kfStart = keyframes[i];
            var kfEnd = keyframes[i + 1];
            double segStart = kfStart.Timestamp;
            double segEnd = kfEnd.Timestamp;
            double segDuration = segEnd - segStart;

            if (segDuration <= 0) continue;

            // Interpolate crop at midpoint of segment for the mask
            double midTime = (segStart + segEnd) / 2.0;
            var keyframeData = keyframes.Select(ToKeyframeData).ToList();
            var state = KeyframeInterpolator.Instance.Interpolate(
                keyframeData, midTime, config.Mode);

            // Generate segment
            string segPath = Path.Combine(Path.GetTempPath(), $"seg_{Guid.NewGuid()}.mov");
            _tempFiles.Add(segPath);

            var segExport = new FFmpegExportService();
            await segExport.ExportVideoAsync(
                video.SourcePath, segPath, metadata,
                config.Mode, state.CropRect,
                state.CircleCenter, state.CircleRadius,
                null, null,
                state.AIMaskData != null ? System.Text.Encoding.UTF8.GetBytes("{}") : null,
                state.AIBoundingBox,
                config.PreserveWidth, config.EnableAlphaChannel,
                p => progressHandler?.Invoke((i + p) / totalSegments),
                token);

            segmentPaths.Add(segPath);
        }

        if (segmentPaths.Count == 0)
            throw new ExportException(ExportError.FFmpegFailed, "No segments to export");

        if (segmentPaths.Count == 1)
        {
            File.Move(segmentPaths[0], outputPath, overwrite: true);
            return outputPath;
        }

        // Concatenate segments
        await ConcatenateSegmentsAsync(segmentPaths, outputPath, token);
        progressHandler?.Invoke(1.0);

        CleanupTempFiles();
        return outputPath;
    }

    private async Task ConcatenateSegmentsAsync(
        List<string> segmentPaths, string outputPath, CancellationToken token)
    {
        var ffmpegPath = FFmpegExportService.FindFFmpeg();
        if (ffmpegPath == null)
            throw new ExportException(ExportError.FFmpegNotFound);

        // Create concat list file
        string concatList = Path.Combine(Path.GetTempPath(), $"concat_{Guid.NewGuid()}.txt");
        _tempFiles.Add(concatList);

        var sb = new StringBuilder();
        foreach (var path in segmentPaths)
        {
            sb.AppendLine($"file '{path.Replace("'", "'\\''")}'");
        }
        await File.WriteAllTextAsync(concatList, sb.ToString(), token);

        var args = new List<string>
        {
            "-y", "-f", "concat", "-safe", "0",
            "-i", concatList,
            "-c", "copy",
            outputPath
        };

        await RunFFmpegWithProgressAsync(ffmpegPath, args, 0, null, token);
    }

    /// <summary>
    /// Builds a piecewise linear FFmpeg expression from keyframes.
    /// Uses if(lt(t,T), V, ...) nesting for each segment.
    /// </summary>
    private static string BuildPiecewiseLinearExpr(
        List<Keyframe> keyframes, Func<Keyframe, double> getValue)
    {
        if (keyframes.Count == 0) return "0";
        if (keyframes.Count == 1) return $"{(int)getValue(keyframes[0])}";

        // Build nested if expressions for piecewise linear interpolation
        var sb = new StringBuilder();
        for (int i = 0; i < keyframes.Count - 1; i++)
        {
            double t0 = keyframes[i].Timestamp;
            double t1 = keyframes[i + 1].Timestamp;
            double v0 = getValue(keyframes[i]);
            double v1 = getValue(keyframes[i + 1]);

            if (Math.Abs(t1 - t0) < 0.001)
            {
                // Same time, use start value
                if (i == keyframes.Count - 2)
                    sb.Append($"{(int)v0}");
                continue;
            }

            // Linear interpolation: v0 + (v1-v0) * (t-t0) / (t1-t0)
            double slope = (v1 - v0) / (t1 - t0);

            if (i < keyframes.Count - 2)
            {
                sb.Append($"if(lt(t,{t1:F4}),");
                if (Math.Abs(slope) < 0.01)
                    sb.Append($"{(int)v0}");
                else
                    sb.Append($"{v0:F1}+{slope:F4}*(t-{t0:F4})");
                sb.Append(',');
            }
            else
            {
                // Last segment
                if (Math.Abs(slope) < 0.01)
                    sb.Append($"{(int)v1}");
                else
                    sb.Append($"{v0:F1}+{slope:F4}*(t-{t0:F4})");
            }
        }

        // Close all if() parens
        for (int i = 0; i < keyframes.Count - 2; i++)
            sb.Append(')');

        return sb.ToString();
    }

    private static string EvenExpr(string expr)
    {
        // Make expression evaluate to even number: floor(expr/2)*2
        return $"floor(({expr})/2)*2";
    }

    private static KeyframeData ToKeyframeData(Keyframe kf)
    {
        return new KeyframeData
        {
            Timestamp = kf.Timestamp,
            CropRect = kf.CropRect,
            EdgeInsets = kf.EdgeInsets,
            CircleCenter = kf.CircleCenter,
            CircleRadius = kf.CircleRadius,
            FreehandPathData = kf.FreehandPathData,
            AIMaskData = kf.AiMaskData,
            AIBoundingBox = kf.AiBoundingBox,
            Interpolation = kf.Interpolation
        };
    }

    private async Task AddCodecArgs(
        List<string> args, VideoMetadata metadata, bool enableAlpha, string ffmpegPath)
    {
        // Simple approach: detect best H.264 encoder
        string[] encoders = { "h264_nvenc", "h264_qsv", "h264_amf", "libx264" };
        string selectedEncoder = "libx264";

        foreach (var encoder in encoders)
        {
            if (encoder == "libx264" || await TestEncoderAsync(ffmpegPath, encoder))
            {
                selectedEncoder = encoder;
                break;
            }
        }

        args.AddRange(new[] { "-c:v", selectedEncoder });

        if (selectedEncoder == "libx264")
            args.AddRange(new[] { "-crf", "18", "-preset", "medium" });
        else
            args.AddRange(new[] { "-b:v", $"{Math.Max(metadata.BitRate, 10_000_000) / 1000}k" });

        if (enableAlpha)
            args.AddRange(new[] { "-pix_fmt", "yuva420p" });
    }

    private static async Task<bool> TestEncoderAsync(string ffmpegPath, string encoderName)
    {
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
            await process.WaitForExitAsync(cts.Token);
            return process.ExitCode == 0;
        }
        catch { return false; }
    }

    private static async Task RunFFmpegWithProgressAsync(
        string ffmpegPath, List<string> args, double duration,
        Action<double>? progressHandler, CancellationToken token)
    {
        var startInfo = new ProcessStartInfo
        {
            FileName = ffmpegPath,
            Arguments = string.Join(" ", args.Select(a =>
                a.Contains(' ') || a.Contains('"') ? $"\"{a.Replace("\"", "\\\"")}\"" : a)),
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        using var process = new Process { StartInfo = startInfo };
        process.Start();

        // Read stdout for progress
        var readTask = Task.Run(async () =>
        {
            using var reader = process.StandardOutput;
            string? line;
            while ((line = await reader.ReadLineAsync(token)) != null)
            {
                if (line.StartsWith("out_time_ms=") && duration > 0)
                {
                    string msStr = line["out_time_ms=".Length..];
                    if (long.TryParse(msStr, out long ms))
                    {
                        double progress = Math.Min(0.99, ms / 1_000_000.0 / duration);
                        progressHandler?.Invoke(progress);
                    }
                }
            }
        }, token);

        // Drain stderr
        var errTask = process.StandardError.ReadToEndAsync(token);

        await process.WaitForExitAsync(token);
        try { await Task.WhenAll(readTask, errTask).WaitAsync(TimeSpan.FromSeconds(5)); } catch { }

        if (token.IsCancellationRequested)
            throw new ExportException(ExportError.Cancelled);

        if (process.ExitCode != 0)
        {
            string stderr = errTask.IsCompletedSuccessfully ? errTask.Result : "";
            throw new ExportException(ExportError.FFmpegFailed,
                $"FFmpeg failed (exit code {process.ExitCode}): {stderr[..Math.Min(stderr.Length, 500)]}", process.ExitCode);
        }

        progressHandler?.Invoke(1.0);
    }

    private void CleanupTempFiles()
    {
        foreach (string path in _tempFiles)
        {
            try { if (File.Exists(path)) File.Delete(path); } catch { }
        }
        _tempFiles.Clear();
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        Cancel();
        _cts?.Dispose();
        _exportService.Dispose();
    }
}
