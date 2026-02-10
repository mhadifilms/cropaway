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
    private CancellationTokenSource? _cancellationSource;

    [RelayCommand]
    public async Task ExportVideo(VideoItem video)
    {
        var config = video.CropConfig;

        // Show save dialog
        var dialog = new SaveFileDialog
        {
            Title = "Export Video",
            FileName = $"{video.FileName}_cropped",
            DefaultExt = ".mov",
            Filter = "QuickTime Movie (*.mov)|*.mov|MP4 Video (*.mp4)|*.mp4|All Files (*.*)|*.*"
        };

        if (dialog.ShowDialog() != true) return;

        var exportConfig = new ExportConfiguration
        {
            PreserveWidth = config.PreserveWidth,
            EnableAlphaChannel = config.EnableAlphaChannel,
            OutputPath = dialog.FileName
        };

        var job = new ExportJob
        {
            Id = Guid.NewGuid(),
            Video = video,
            OutputPath = dialog.FileName,
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

            var outputPath = Path.Combine(folder, $"{video.FileName}_cropped.mov");
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
                exportConfig.OutputPath,
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

    [RelayCommand]
    public async Task ExportCropJson(VideoItem video)
    {
        var dialog = new System.Windows.Forms.FolderBrowserDialog
        {
            Description = "Export Crop JSON to Folder"
        };

        if (dialog.ShowDialog() != System.Windows.Forms.DialogResult.OK) return;

        try
        {
            var document = CropDataStorageService.Instance.Load(video.SourcePath);
            if (document == null)
            {
                StatusMessage = "No crop data to export";
                return;
            }
            var path = CropDataStorageService.Instance.ExportToFolder(document, dialog.SelectedPath, video.FileName);
            StatusMessage = $"Crop data exported to {Path.GetFileName(path)}";
        }
        catch (Exception ex)
        {
            StatusMessage = $"Export failed: {ex.Message}";
        }
    }

    [RelayCommand]
    public async Task ExportBoundingBoxJson(VideoItem video)
    {
        var dialog = new System.Windows.Forms.FolderBrowserDialog
        {
            Description = "Export Bounding Box JSON to Folder"
        };

        if (dialog.ShowDialog() != System.Windows.Forms.DialogResult.OK) return;

        try
        {
            var document = CropDataStorageService.Instance.Load(video.SourcePath);
            if (document == null)
            {
                StatusMessage = "No crop data to export";
                return;
            }
            var path = CropDataStorageService.Instance.ExportToFolder(document, dialog.SelectedPath, video.FileName);
            StatusMessage = $"Bounding box data exported to {Path.GetFileName(path)}";
        }
        catch (Exception ex)
        {
            StatusMessage = $"Export failed: {ex.Message}";
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
