using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Media;
using CropawayWindows.Services;

namespace CropawayWindows.Views;

/// <summary>
/// About dialog showing app info, FFmpeg status, and GPU encoder availability.
/// </summary>
public partial class AboutWindow : Window
{
    public AboutWindow()
    {
        InitializeComponent();
        Loaded += OnLoaded;
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        // Set copyright year
        CopyrightText.Text = $"\u00a9 {DateTime.Now.Year} Cropaway. All rights reserved.";

        // Check FFmpeg status
        UpdateFFmpegStatus();

        // Detect GPU encoders
        await DetectEncodersAsync();
    }

    private void UpdateFFmpegStatus()
    {
        string? ffmpegPath = FFmpegExportService.FindFFmpeg();

        if (ffmpegPath != null)
        {
            string version = GetFFmpegVersionShort(ffmpegPath);
            FFmpegStatusIcon.Text = "\uE73E"; // Check icon
            FFmpegStatusIcon.Foreground = (Brush)FindResource("ExportProgressBrush");

            if (!string.IsNullOrEmpty(version))
            {
                FFmpegStatusText.Text = version;
                FFmpegStatusText.Foreground = (Brush)FindResource("TextPrimaryBrush");
            }
            else
            {
                FFmpegStatusText.Text = $"Found at {ffmpegPath}";
                FFmpegStatusText.Foreground = (Brush)FindResource("TextPrimaryBrush");
            }
        }
        else
        {
            FFmpegStatusIcon.Text = "\uE783"; // Error icon
            FFmpegStatusIcon.Foreground = (Brush)FindResource("ErrorBrush");
            FFmpegStatusText.Text = "Not found";
            FFmpegStatusText.Foreground = (Brush)FindResource("ErrorBrush");
        }
    }

    private async Task DetectEncodersAsync()
    {
        string? ffmpegPath = FFmpegExportService.FindFFmpeg();

        if (ffmpegPath == null)
        {
            EncoderStatusText.Text = "Cannot detect encoders (FFmpeg not found)";
            EncoderStatusText.Foreground = (Brush)FindResource("TextTertiaryBrush");
            return;
        }

        try
        {
            var encoders = new List<string>();

            // Test H.264 hardware encoders
            string[] h264Encoders = { "h264_nvenc", "h264_qsv", "h264_amf" };
            foreach (string encoder in h264Encoders)
            {
                if (await IsEncoderAvailableAsync(ffmpegPath, encoder))
                {
                    encoders.Add(GetEncoderDisplayName(encoder));
                }
            }

            // Test HEVC hardware encoders
            string[] hevcEncoders = { "hevc_nvenc", "hevc_qsv", "hevc_amf" };
            foreach (string encoder in hevcEncoders)
            {
                if (await IsEncoderAvailableAsync(ffmpegPath, encoder))
                {
                    encoders.Add(GetEncoderDisplayName(encoder));
                }
            }

            if (encoders.Count > 0)
            {
                EncoderStatusText.Text = string.Join("\n", encoders);
                EncoderStatusText.Foreground = (Brush)FindResource("TextPrimaryBrush");
            }
            else
            {
                EncoderStatusText.Text = "No GPU encoders detected. Software encoding (libx264/libx265) will be used.";
                EncoderStatusText.Foreground = (Brush)FindResource("TextSecondaryBrush");
            }
        }
        catch
        {
            EncoderStatusText.Text = "Failed to detect encoders.";
            EncoderStatusText.Foreground = (Brush)FindResource("TextTertiaryBrush");
        }
    }

    private static async Task<bool> IsEncoderAvailableAsync(string ffmpegPath, string encoderName)
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

    private static string GetEncoderDisplayName(string encoder) => encoder switch
    {
        "h264_nvenc" => "NVIDIA NVENC H.264",
        "h264_qsv" => "Intel Quick Sync H.264",
        "h264_amf" => "AMD AMF H.264",
        "hevc_nvenc" => "NVIDIA NVENC HEVC",
        "hevc_qsv" => "Intel Quick Sync HEVC",
        "hevc_amf" => "AMD AMF HEVC",
        _ => encoder
    };

    private static string GetFFmpegVersionShort(string ffmpegPath)
    {
        try
        {
            using var process = new Process();
            process.StartInfo = new ProcessStartInfo
            {
                FileName = ffmpegPath,
                Arguments = "-version",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            process.Start();
            string output = process.StandardOutput.ReadLine() ?? "";
            process.WaitForExit(3000);

            // Parse version from "ffmpeg version X.X.X-..."
            if (output.StartsWith("ffmpeg version "))
            {
                string versionPart = output["ffmpeg version ".Length..];
                // Take up to the first space or hyphen after the version numbers
                int endIdx = versionPart.IndexOfAny(new[] { ' ', '-' });
                if (endIdx > 0)
                    return $"FFmpeg {versionPart[..endIdx]}";
                return $"FFmpeg {versionPart}";
            }

            return "";
        }
        catch
        {
            return "";
        }
    }

    private void OnCloseClick(object sender, RoutedEventArgs e)
    {
        Close();
    }
}
