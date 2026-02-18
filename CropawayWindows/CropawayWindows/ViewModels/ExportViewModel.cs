using System.Collections.ObjectModel;
using System.IO;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CropawayWindows.Models;
using CropawayWindows.Services;
using Microsoft.Win32;

namespace CropawayWindows.ViewModels;

public partial class ExportViewModel : ObservableObject
{
    [ObservableProperty]
    private ObservableCollection<ExportJob> _exportQueue = new();

    [ObservableProperty]
    private ExportJob? _currentExport;

    [ObservableProperty]
    private bool _isExporting;

    [ObservableProperty]
    private double _overallProgress;

    [ObservableProperty]
    private string _statusMessage = "";

    [ObservableProperty]
    private int _completedCount;

    [ObservableProperty]
    private int _totalBatchCount;

    [ObservableProperty]
    private bool _isBatchExport;

    private readonly FFmpegExportService _exportService = new();
    private readonly BoundingBoxExportService _boundingBoxExportService = new();
    private CancellationTokenSource? _cancellationSource;

    [RelayCommand]
    public async Task ExportVideo(VideoItem video)
    {
        var config = video.CropConfig;

        // When alpha channel is enabled, force .mov for ProRes 4444 compatibility
        string defaultExt;
        string filter;
        if (config.EnableAlphaChannel)
        {
            defaultExt = ".mov";
            filter = "QuickTime Movie (*.mov)|*.mov|All Files (*.*)|*.*";
        }
        else
        {
            defaultExt = ".mov";
            filter = "QuickTime Movie (*.mov)|*.mov|MP4 Video (*.mp4)|*.mp4|All Files (*.*)|*.*";
        }

        // Show save dialog
        var dialog = new SaveFileDialog
        {
            Title = "Export Video",
            FileName = $"{video.FileName}_cropped",
            DefaultExt = defaultExt,
            Filter = filter
        };

        if (dialog.ShowDialog() != true) return;

        // If alpha is enabled but user chose a non-.mov extension, force .mov
        string outputPath = dialog.FileName;
        if (config.EnableAlphaChannel)
        {
            string ext = Path.GetExtension(outputPath).ToLowerInvariant();
            if (ext != ".mov")
            {
                outputPath = Path.ChangeExtension(outputPath, ".mov");
            }
        }

        var exportConfig = new ExportConfiguration
        {
            PreserveWidth = config.PreserveWidth,
            EnableAlphaChannel = config.EnableAlphaChannel,
            OutputPath = outputPath
        };

        var job = new ExportJob
        {
            Id = Guid.NewGuid(),
            Video = video,
            OutputPath = outputPath,
            Status = ExportStatus.Queued
        };

        ExportQueue.Add(job);
        await ProcessExportJob(job, exportConfig);
    }

    [RelayCommand]
    public async Task ExportAll(IEnumerable<VideoItem> videos)
    {
        // Choose output folder
        var dialog = new System.Windows.Forms.FolderBrowserDialog
        {
            Description = "Select Export Folder",
            ShowNewFolderButton = true
        };

        if (dialog.ShowDialog() != System.Windows.Forms.DialogResult.OK) return;

        var folder = dialog.SelectedPath;
        var videosToExport = videos.Where(v => v.HasCropChanges).ToList();

        if (videosToExport.Count == 0)
        {
            StatusMessage = "No videos with crop changes to export";
            return;
        }

        IsBatchExport = true;
        TotalBatchCount = videosToExport.Count;
        CompletedCount = 0;

        foreach (var video in videosToExport)
        {
            if (_cancellationSource?.Token.IsCancellationRequested == true) break;

            // Use .mov for alpha channel exports (ProRes 4444 required)
            string ext = video.CropConfig.EnableAlphaChannel ? ".mov" : ".mov";
            var outputPath = Path.Combine(folder, $"{video.FileName}_cropped{ext}");
            var config = new ExportConfiguration
            {
                PreserveWidth = video.CropConfig.PreserveWidth,
                EnableAlphaChannel = video.CropConfig.EnableAlphaChannel,
                OutputPath = outputPath
            };

            var job = new ExportJob
            {
                Id = Guid.NewGuid(),
                Video = video,
                OutputPath = outputPath,
                Status = ExportStatus.Queued
            };

            ExportQueue.Add(job);
            await ProcessExportJob(job, config);

            if (job.Status == ExportStatus.Completed)
                CompletedCount++;
        }

        IsBatchExport = false;
        StatusMessage = $"Batch export complete: {CompletedCount}/{TotalBatchCount} videos exported";

        // Show toast notification and play completion sound for the batch
        NotificationService.Instance.ShowExportCompleteNotification(
            $"{CompletedCount} of {TotalBatchCount} videos", folder);
    }

    private async Task ProcessExportJob(ExportJob job, ExportConfiguration exportConfig)
    {
        CurrentExport = job;
        IsExporting = true;
        job.Status = ExportStatus.Processing;
        _cancellationSource = new CancellationTokenSource();

        try
        {
            StatusMessage = $"Exporting {job.Video.FileName}...";

            var video = job.Video;
            var crop = video.CropConfig;

            var outputPath = await _exportService.ExportVideoAsync(
                video.SourcePath,
                exportConfig.OutputPath ?? throw new InvalidOperationException("Output path not set"),
                video.Metadata,
                crop.Mode,
                crop.CropRect,
                crop.CircleCenter,
                crop.CircleRadius,
                crop.FreehandPoints.Count > 0 ? crop.FreehandPoints : null,
                crop.FreehandPathData,
                crop.AiMaskData,
                crop.AiBoundingBox,
                exportConfig.PreserveWidth,
                exportConfig.EnableAlphaChannel,
                progress =>
                {
                    System.Windows.Application.Current.Dispatcher.Invoke(() =>
                    {
                        job.Progress = progress;
                        OverallProgress = progress;
                        StatusMessage = $"Exporting {video.FileName}... {progress:P0}";
                    });
                },
                _cancellationSource.Token);

            job.Status = ExportStatus.Completed;
            job.Progress = 1.0;
            job.Video.LastExportPath = outputPath;
            job.Video.LastExportDate = DateTime.Now;

            StatusMessage = $"Export complete: {Path.GetFileName(outputPath)}";

            // Show toast notification and play completion sound
            if (!IsBatchExport)
            {
                NotificationService.Instance.ShowExportCompleteNotification(
                    job.Video.FileName, outputPath);
            }
        }
        catch (OperationCanceledException)
        {
            job.Status = ExportStatus.Cancelled;
            StatusMessage = "Export cancelled";
        }
        catch (Exception ex)
        {
            job.Status = ExportStatus.Failed;
            job.ErrorMessage = ex.Message;
            StatusMessage = $"Export failed: {ex.Message}";
        }
        finally
        {
            IsExporting = false;
            _cancellationSource?.Dispose();
            _cancellationSource = null;
        }
    }

    [RelayCommand]
    public void CancelExport()
    {
        _cancellationSource?.Cancel();
        _exportService.Cancel();
    }

    public void ExportBoundingBoxJson(VideoItem video)
    {
        if (video.Metadata.Width <= 0 || video.Metadata.Height <= 0)
        {
            StatusMessage = "Cannot export: video metadata not loaded (ensure FFmpeg/ffprobe is installed)";
            System.Windows.MessageBox.Show(
                "Video metadata is missing dimensions. Make sure FFmpeg (ffprobe) is installed and the video loaded correctly.",
                "Export Error", System.Windows.MessageBoxButton.OK, System.Windows.MessageBoxImage.Warning);
            return;
        }

        var dialog = new SaveFileDialog
        {
            Title = "Export Bounding Box JSON",
            FileName = $"{video.FileName}_bbox",
            DefaultExt = ".json",
            Filter = "JSON File (*.json)|*.json|All Files (*.*)|*.*"
        };

        if (dialog.ShowDialog() != true) return;

        try
        {
            _boundingBoxExportService.ExportAsJson(video.CropConfig, video.Metadata, dialog.FileName);
            StatusMessage = $"Bounding box JSON exported: {Path.GetFileName(dialog.FileName)} " +
                            $"({video.Metadata.TotalFrameCount} frames, {video.Metadata.Width}x{video.Metadata.Height})";
        }
        catch (Exception ex)
        {
            StatusMessage = $"Bounding box export failed: {ex.Message}";
            System.Windows.MessageBox.Show(ex.Message, "Export Error",
                System.Windows.MessageBoxButton.OK, System.Windows.MessageBoxImage.Error);
        }
    }

    public void ExportBoundingBoxPickle(VideoItem video)
    {
        if (video.Metadata.Width <= 0 || video.Metadata.Height <= 0)
        {
            StatusMessage = "Cannot export: video metadata not loaded (ensure FFmpeg/ffprobe is installed)";
            System.Windows.MessageBox.Show(
                "Video metadata is missing dimensions. Make sure FFmpeg (ffprobe) is installed and the video loaded correctly.",
                "Export Error", System.Windows.MessageBoxButton.OK, System.Windows.MessageBoxImage.Warning);
            return;
        }

        var dialog = new SaveFileDialog
        {
            Title = "Export Bounding Box Pickle",
            FileName = $"{video.FileName}_bbox",
            DefaultExt = ".pkl",
            Filter = "Python Pickle (*.pkl)|*.pkl|All Files (*.*)|*.*"
        };

        if (dialog.ShowDialog() != true) return;

        try
        {
            _boundingBoxExportService.ExportAsPickle(video.CropConfig, video.Metadata, dialog.FileName);
            StatusMessage = $"Bounding box pickle exported: {Path.GetFileName(dialog.FileName)} " +
                            $"({video.Metadata.TotalFrameCount} frames, {video.Metadata.Width}x{video.Metadata.Height})";
        }
        catch (Exception ex)
        {
            StatusMessage = $"Bounding box export failed: {ex.Message}";
            System.Windows.MessageBox.Show(ex.Message, "Export Error",
                System.Windows.MessageBoxButton.OK, System.Windows.MessageBoxImage.Error);
        }
    }
}

public partial class ExportJob : ObservableObject
{
    public Guid Id { get; set; }
    public VideoItem Video { get; set; } = null!;
    public string OutputPath { get; set; } = "";

    [ObservableProperty]
    private double _progress;

    [ObservableProperty]
    private ExportStatus _status = ExportStatus.Queued;

    [ObservableProperty]
    private string? _errorMessage;
}

public enum ExportStatus
{
    Queued,
    Processing,
    Completed,
    Failed,
    Cancelled
}
