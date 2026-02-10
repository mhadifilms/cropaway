using System.Collections.ObjectModel;
using System.IO;
using System.Windows;
using System.Windows.Media.Imaging;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CropawayWindows.Models;
using CropawayWindows.Services;
using Microsoft.Win32;

namespace CropawayWindows.ViewModels;

public partial class ProjectViewModel : ObservableObject
{
    [ObservableProperty]
    private ObservableCollection<VideoItem> _videos = new();

    [ObservableProperty]
    private VideoItem? _selectedVideo;

    [ObservableProperty]
    private bool _isLoading;

    [ObservableProperty]
    private string _statusMessage = "Ready";

    private static readonly string[] SupportedExtensions =
    {
        ".mp4", ".mov", ".avi", ".mkv", ".webm", ".m4v", ".wmv",
        ".flv", ".mxf", ".ts", ".mts", ".m2ts", ".3gp", ".prores"
    };

    partial void OnSelectedVideoChanged(VideoItem? value)
    {
        if (value != null)
        {
            StatusMessage = $"Selected: {value.FileName}";
        }
    }

    [RelayCommand]
    private async Task OpenVideos()
    {
        var dialog = new OpenFileDialog
        {
            Title = "Add Videos",
            Filter = BuildFileFilter(),
            Multiselect = true
        };

        if (dialog.ShowDialog() == true)
        {
            await AddVideosFromPaths(dialog.FileNames);
        }
    }

    public async Task AddVideosFromPaths(IEnumerable<string> paths)
    {
        IsLoading = true;
        StatusMessage = "Loading videos...";

        var newVideos = new List<VideoItem>();

        foreach (var path in paths)
        {
            var ext = Path.GetExtension(path).ToLowerInvariant();
            if (!SupportedExtensions.Contains(ext)) continue;

            // Skip duplicates
            if (Videos.Any(v => v.SourcePath == path)) continue;

            var video = new VideoItem
            {
                Id = Guid.NewGuid(),
                SourcePath = path,
                FileName = Path.GetFileNameWithoutExtension(path),
                DateAdded = DateTime.Now,
                IsLoading = true,
                Metadata = new VideoMetadata(),
                CropConfig = new CropConfiguration()
            };

            newVideos.Add(video);
            Videos.Add(video);
        }

        // Load metadata and thumbnails in parallel
        var tasks = newVideos.Select(async video =>
        {
            try
            {
                // Extract metadata using ffprobe
                var metadata = await VideoMetadataExtractor.Instance.ExtractMetadataAsync(video.SourcePath);
                video.Metadata = metadata;

                // Generate thumbnail
                var thumbnail = await GenerateThumbnailAsync(video.SourcePath);
                if (thumbnail != null)
                {
                    Application.Current.Dispatcher.Invoke(() =>
                    {
                        video.Thumbnail = thumbnail;
                    });
                }

                // Load saved crop data
                var savedData = CropDataStorageService.Instance.Load(video.SourcePath);
                if (savedData != null)
                {
                    Application.Current.Dispatcher.Invoke(() =>
                    {
                        var mode = CropDataStorageService.Instance.Apply(
                            savedData,
                            out var cropRect,
                            out var circleCenter,
                            out var circleRadius,
                            out var freehandPoints,
                            out var freehandPathData,
                            out var aiMaskData,
                            out var aiBoundingBox,
                            out var aiTextPrompt,
                            out var aiConfidence,
                            out var keyframeDataList,
                            out var keyframesEnabled);

                        var config = video.CropConfig;
                        config.Mode = mode;
                        config.CropRect = cropRect;
                        config.CircleCenter = circleCenter;
                        config.CircleRadius = circleRadius;
                        config.AiBoundingBox = aiBoundingBox;
                        config.AiTextPrompt = aiTextPrompt;
                        config.KeyframesEnabled = keyframesEnabled;
                    });
                }

                video.IsLoading = false;
            }
            catch (Exception ex)
            {
                video.LoadError = ex.Message;
                video.IsLoading = false;
            }
        });

        await Task.WhenAll(tasks);

        IsLoading = false;
        StatusMessage = $"{Videos.Count} video{(Videos.Count == 1 ? "" : "s")} loaded";

        // Auto-select first video if none selected
        if (SelectedVideo == null && Videos.Count > 0)
        {
            SelectedVideo = Videos[0];
        }
    }

    [RelayCommand]
    private void RemoveSelectedVideo()
    {
        if (SelectedVideo == null) return;

        var index = Videos.IndexOf(SelectedVideo);
        Videos.Remove(SelectedVideo);

        // Select adjacent video
        if (Videos.Count > 0)
        {
            SelectedVideo = Videos[Math.Min(index, Videos.Count - 1)];
        }
        else
        {
            SelectedVideo = null;
        }
    }

    [RelayCommand]
    private void SelectNextVideo()
    {
        if (SelectedVideo == null || Videos.Count <= 1) return;
        var index = Videos.IndexOf(SelectedVideo);
        if (index < Videos.Count - 1)
        {
            SelectedVideo = Videos[index + 1];
        }
    }

    [RelayCommand]
    private void SelectPreviousVideo()
    {
        if (SelectedVideo == null || Videos.Count <= 1) return;
        var index = Videos.IndexOf(SelectedVideo);
        if (index > 0)
        {
            SelectedVideo = Videos[index - 1];
        }
    }

    public void HandleFileDrop(string[] files)
    {
        var validPaths = files.Where(f =>
        {
            var ext = Path.GetExtension(f).ToLowerInvariant();
            return SupportedExtensions.Contains(ext);
        }).ToArray();

        if (validPaths.Length > 0)
        {
            _ = AddVideosFromPaths(validPaths);
        }
    }

    private static async Task<BitmapSource?> GenerateThumbnailAsync(string videoPath)
    {
        return await Task.Run(() =>
        {
            try
            {
                var ffmpegPath = FFmpegExportService.FindFFmpeg();
                if (ffmpegPath == null) return null;

                // Use ffmpeg to extract first frame as BMP to stdout
                var ffmpegDir = Path.GetDirectoryName(ffmpegPath)!;
                var ffmpegExe = Path.Combine(ffmpegDir, "ffmpeg" + (OperatingSystem.IsWindows() ? ".exe" : ""));

                if (!File.Exists(ffmpegExe))
                    ffmpegExe = ffmpegPath.Replace("ffprobe", "ffmpeg");

                var tempFile = Path.Combine(Path.GetTempPath(), $"thumb_{Guid.NewGuid()}.jpg");

                var process = new System.Diagnostics.Process
                {
                    StartInfo = new System.Diagnostics.ProcessStartInfo
                    {
                        FileName = ffmpegExe,
                        Arguments = $"-y -i \"{videoPath}\" -ss 0 -vframes 1 -vf \"scale=200:-1\" \"{tempFile}\"",
                        CreateNoWindow = true,
                        UseShellExecute = false,
                        RedirectStandardError = true
                    }
                };

                process.Start();
                process.WaitForExit(10000);

                if (File.Exists(tempFile))
                {
                    var bitmap = new BitmapImage();
                    bitmap.BeginInit();
                    bitmap.CacheOption = BitmapCacheOption.OnLoad;
                    bitmap.UriSource = new Uri(tempFile);
                    bitmap.EndInit();
                    bitmap.Freeze();

                    // Clean up temp file
                    try { File.Delete(tempFile); } catch { }

                    return (BitmapSource)bitmap;
                }
            }
            catch
            {
                // Thumbnail generation failed - not critical
            }

            return null;
        });
    }

    private static string BuildFileFilter()
    {
        var extensions = SupportedExtensions.Select(e => $"*{e}").ToArray();
        return $"Video Files ({string.Join(", ", extensions)})|{string.Join(";", extensions)}|All Files (*.*)|*.*";
    }
}
