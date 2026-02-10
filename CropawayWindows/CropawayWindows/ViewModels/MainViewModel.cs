using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Input;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CropawayWindows.Models;
using CropawayWindows.Services;

namespace CropawayWindows.ViewModels;

/// <summary>
/// Top-level ViewModel that coordinates all sub-ViewModels.
/// Equivalent to the macOS app's MainContentView coordinator.
/// </summary>
public partial class MainViewModel : ObservableObject
{
    public ProjectViewModel Project { get; } = new();
    public VideoPlayerViewModel Player { get; } = new();
    public CropEditorViewModel CropEditor { get; } = new();
    public KeyframeViewModel Keyframes { get; } = new();
    public ExportViewModel Export { get; } = new();
    public TimelineViewModel Timeline { get; } = new();
    public CropUndoManager UndoManager { get; } = new();

    [ObservableProperty]
    private bool _isSidebarVisible = true;

    [ObservableProperty]
    private bool _isKeyframePanelVisible;

    [ObservableProperty]
    private bool _isTimelinePanelVisible;

    [ObservableProperty]
    private double _zoomLevel = 1.0;

    [ObservableProperty]
    private string _statusBarText = "Ready - Drop videos here or use File > Open";

    [ObservableProperty]
    private bool _isFullScreen;

    [ObservableProperty]
    private bool _isAIPanelVisible;

    // Auto-save debounce
    private CancellationTokenSource? _autoSaveCts;
    private const int AutoSaveDebounceMs = 500;

    // Copied crop configuration for paste
    private CropConfiguration? _copiedCropConfig;

    public MainViewModel()
    {
        // Wire up sub-ViewModels
        Keyframes.Initialize(CropEditor, Player);
        Timeline.Initialize(Player, Project);

        // React to video selection changes
        Project.PropertyChanged += (s, e) =>
        {
            if (e.PropertyName == nameof(Project.SelectedVideo))
            {
                OnSelectedVideoChanged();
            }
        };

        // React to crop mode changes to show/hide AI panel
        CropEditor.PropertyChanged += (s, e) =>
        {
            if (e.PropertyName == nameof(CropEditor.Mode))
            {
                IsAIPanelVisible = CropEditor.Mode == CropMode.AI;
            }
        };

        // Auto-save crop data when crop properties change (debounced)
        CropEditor.PropertyChanged += (s, e) =>
        {
            if (e.PropertyName is nameof(CropEditor.CropRect) or
                nameof(CropEditor.CircleCenter) or
                nameof(CropEditor.CircleRadius) or
                nameof(CropEditor.FreehandPoints) or
                nameof(CropEditor.AiMaskData) or
                nameof(CropEditor.AiBoundingBox) or
                nameof(CropEditor.Mode) or
                nameof(CropEditor.PreserveWidth) or
                nameof(CropEditor.EnableAlphaChannel))
            {
                ScheduleAutoSave();
            }
        };

        // React to player time changes for keyframe interpolation
        Player.PropertyChanged += (s, e) =>
        {
            if (e.PropertyName == nameof(Player.CurrentTime))
            {
                Keyframes.UpdateCurrentTime(Player.CurrentTime);
            }
        };

        // React to export status
        Export.PropertyChanged += (s, e) =>
        {
            if (e.PropertyName == nameof(Export.StatusMessage))
            {
                StatusBarText = Export.StatusMessage;
            }
        };

        Project.PropertyChanged += (s, e) =>
        {
            if (e.PropertyName == nameof(Project.StatusMessage))
            {
                StatusBarText = Project.StatusMessage;
            }
        };
    }

    private void OnSelectedVideoChanged()
    {
        var video = Project.SelectedVideo;
        if (video == null) return;

        // Bind all ViewModels to new video
        Player.LoadVideo(video);
        CropEditor.BindTo(video);
        Keyframes.BindTo(video);
        UndoManager.BindTo(video);

        StatusBarText = $"{video.FileName} - {video.Metadata.Width}x{video.Metadata.Height} @ {video.Metadata.FrameRate:F2}fps";
    }

    // MARK: - Auto-save

    private void ScheduleAutoSave()
    {
        _autoSaveCts?.Cancel();
        _autoSaveCts = new CancellationTokenSource();
        var token = _autoSaveCts.Token;

        Task.Delay(AutoSaveDebounceMs, token).ContinueWith(t =>
        {
            if (t.IsCanceled) return;
            Application.Current?.Dispatcher.Invoke(SaveCropData);
        }, TaskScheduler.Default);
    }

    private void SaveCropData()
    {
        var video = Project.SelectedVideo;
        if (video == null) return;

        try
        {
            var config = video.CropConfig;
            var keyframeData = config.Keyframes
                .Select(kf => new KeyframeData
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
                }).ToList();

            var document = CropDataStorageService.Instance.CreateDocument(
                video.SourcePath,
                video.Metadata,
                CropEditor.Mode,
                CropEditor.CropRect,
                CropEditor.CircleCenter,
                CropEditor.CircleRadius,
                CropEditor.FreehandPoints.Count > 0 ? CropEditor.FreehandPoints : null,
                CropEditor.FreehandPathData,
                CropEditor.AiMaskData,
                CropEditor.AiBoundingBox,
                CropEditor.AiTextPrompt,
                config.AiConfidence,
                keyframeData,
                Keyframes.KeyframesEnabled);

            CropDataStorageService.Instance.Save(document, video.SourcePath);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"Auto-save failed: {ex.Message}");
        }
    }

    // MARK: - Commands

    [RelayCommand]
    private void ToggleSidebar() => IsSidebarVisible = !IsSidebarVisible;

    [RelayCommand]
    private void ToggleKeyframePanel() => IsKeyframePanelVisible = !IsKeyframePanelVisible;

    [RelayCommand]
    private void ToggleTimelinePanel() => IsTimelinePanelVisible = !IsTimelinePanelVisible;

    [RelayCommand]
    private void ToggleFullScreen() => IsFullScreen = !IsFullScreen;

    [RelayCommand]
    private void Undo()
    {
        UndoManager.Undo();
        // Re-sync editor from config
        if (Project.SelectedVideo != null)
            CropEditor.BindTo(Project.SelectedVideo);
    }

    [RelayCommand]
    private void Redo()
    {
        UndoManager.Redo();
        if (Project.SelectedVideo != null)
            CropEditor.BindTo(Project.SelectedVideo);
    }

    [RelayCommand]
    private void ZoomIn()
    {
        ZoomLevel = Math.Min(8.0, ZoomLevel * 1.25);
    }

    [RelayCommand]
    private void ZoomOut()
    {
        ZoomLevel = Math.Max(0.1, ZoomLevel / 1.25);
    }

    [RelayCommand]
    private void ZoomToFit()
    {
        ZoomLevel = 1.0;
    }

    [RelayCommand]
    private void ActualSize()
    {
        ZoomLevel = 1.0;
    }

    [RelayCommand]
    private async Task ExportCurrentVideo()
    {
        if (Project.SelectedVideo != null)
        {
            UndoManager.SaveState();
            await Export.ExportVideo(Project.SelectedVideo);
        }
    }

    [RelayCommand]
    private async Task ExportCropJson()
    {
        if (Project.SelectedVideo != null)
        {
            await Export.ExportCropJson(Project.SelectedVideo);
        }
    }

    [RelayCommand]
    private void ResetCrop()
    {
        UndoManager.SaveState();
        CropEditor.Reset();
    }

    [RelayCommand]
    private void AddKeyframe()
    {
        UndoManager.SaveState();
        Keyframes.AddKeyframe();
    }

    [RelayCommand]
    private void RemoveKeyframe()
    {
        UndoManager.SaveState();
        Keyframes.RemoveKeyframe();
    }

    [RelayCommand]
    private void SetCropMode(string modeStr)
    {
        if (Enum.TryParse<CropMode>(modeStr, out var mode))
        {
            UndoManager.SaveState();
            CropEditor.Mode = mode;
        }
    }

    [RelayCommand]
    private void AddToSequence()
    {
        if (Project.SelectedVideo != null)
        {
            Timeline.AddClipFromVideo(Project.SelectedVideo);
        }
    }

    [RelayCommand]
    private void CopyCropSettings()
    {
        if (Project.SelectedVideo == null) return;

        var src = Project.SelectedVideo.CropConfig;
        _copiedCropConfig = new CropConfiguration
        {
            Mode = src.Mode,
            CropRect = src.CropRect,
            EdgeInsets = src.EdgeInsets,
            CircleCenter = src.CircleCenter,
            CircleRadius = src.CircleRadius,
            FreehandPoints = src.FreehandPoints.ToList(),
            FreehandPathData = src.FreehandPathData is not null ? (byte[])src.FreehandPathData.Clone() : null,
            AiMaskData = src.AiMaskData is not null ? (byte[])src.AiMaskData.Clone() : null,
            AiBoundingBox = src.AiBoundingBox,
            AiTextPrompt = src.AiTextPrompt,
            PreserveWidth = src.PreserveWidth,
            EnableAlphaChannel = src.EnableAlphaChannel
        };

        StatusBarText = "Crop settings copied";
    }

    [RelayCommand]
    private void PasteCropSettings()
    {
        if (_copiedCropConfig == null || Project.SelectedVideo == null) return;

        UndoManager.SaveState();

        var dest = Project.SelectedVideo.CropConfig;
        dest.Mode = _copiedCropConfig.Mode;
        dest.CropRect = _copiedCropConfig.CropRect;
        dest.EdgeInsets = _copiedCropConfig.EdgeInsets;
        dest.CircleCenter = _copiedCropConfig.CircleCenter;
        dest.CircleRadius = _copiedCropConfig.CircleRadius;
        dest.FreehandPoints = _copiedCropConfig.FreehandPoints.ToList();
        dest.FreehandPathData = _copiedCropConfig.FreehandPathData is not null
            ? (byte[])_copiedCropConfig.FreehandPathData.Clone() : null;
        dest.AiMaskData = _copiedCropConfig.AiMaskData is not null
            ? (byte[])_copiedCropConfig.AiMaskData.Clone() : null;
        dest.AiBoundingBox = _copiedCropConfig.AiBoundingBox;
        dest.AiTextPrompt = _copiedCropConfig.AiTextPrompt;
        dest.PreserveWidth = _copiedCropConfig.PreserveWidth;
        dest.EnableAlphaChannel = _copiedCropConfig.EnableAlphaChannel;

        // Re-bind editor to reflect pasted settings
        CropEditor.BindTo(Project.SelectedVideo);
        StatusBarText = "Crop settings pasted";
    }

    [RelayCommand]
    private void RevealInExplorer()
    {
        var path = Project.SelectedVideo?.LastExportPath;
        if (!string.IsNullOrEmpty(path) && File.Exists(path))
        {
            Process.Start("explorer.exe", $"/select,\"{path}\"");
        }
    }

    [RelayCommand]
    private async Task ExportAll()
    {
        await Export.ExportAll(Project.Videos);
    }

    [RelayCommand]
    private void ShowSettings()
    {
        var window = new Views.SettingsWindow { Owner = Application.Current.MainWindow };
        window.ShowDialog();
    }

    [RelayCommand]
    private void ShowAbout()
    {
        var window = new Views.AboutWindow { Owner = Application.Current.MainWindow };
        window.ShowDialog();
    }

    // Handle keyboard shortcuts
    public void HandleKeyDown(KeyEventArgs e)
    {
        var ctrl = (Keyboard.Modifiers & ModifierKeys.Control) != 0;
        var shift = (Keyboard.Modifiers & ModifierKeys.Shift) != 0;
        var alt = (Keyboard.Modifiers & ModifierKeys.Alt) != 0;

        switch (e.Key)
        {
            // Playback
            case Key.Space:
                Player.TogglePlayPause();
                e.Handled = true;
                break;
            case Key.Right when !ctrl:
                Player.StepForward();
                e.Handled = true;
                break;
            case Key.Left when !ctrl:
                Player.StepBackward();
                e.Handled = true;
                break;
            case Key.J when !ctrl:
                Player.ShuttleReverse();
                e.Handled = true;
                break;
            case Key.K when !ctrl && !shift:
                Player.ShuttleStop();
                e.Handled = true;
                break;
            case Key.L when !ctrl:
                Player.ShuttleForward();
                e.Handled = true;
                break;

            // Crop modes (Ctrl+1/2/3/4)
            case Key.D1 when ctrl:
                SetCropMode("Rectangle");
                e.Handled = true;
                break;
            case Key.D2 when ctrl:
                SetCropMode("Circle");
                e.Handled = true;
                break;
            case Key.D3 when ctrl:
                SetCropMode("Freehand");
                e.Handled = true;
                break;
            case Key.D4 when ctrl:
                SetCropMode("AI");
                e.Handled = true;
                break;

            // Keyframes
            case Key.K when ctrl && !shift:
                AddKeyframe();
                e.Handled = true;
                break;
            case Key.K when ctrl && shift:
                RemoveKeyframe();
                e.Handled = true;
                break;

            // Edit
            case Key.Z when ctrl && !shift:
                Undo();
                e.Handled = true;
                break;
            case Key.Z when ctrl && shift:
                Redo();
                e.Handled = true;
                break;
            case Key.R when ctrl && shift:
                ResetCrop();
                e.Handled = true;
                break;

            // File
            case Key.N when ctrl:
            case Key.O when ctrl:
                Project.OpenVideosCommand.Execute(null);
                e.Handled = true;
                break;
            case Key.E when ctrl && !alt:
                _ = ExportCurrentVideo();
                e.Handled = true;
                break;
            case Key.J when ctrl && shift:
                _ = ExportCropJson();
                e.Handled = true;
                break;

            // View
            case Key.OemPlus when ctrl:
                ZoomIn();
                e.Handled = true;
                break;
            case Key.OemMinus when ctrl:
                ZoomOut();
                e.Handled = true;
                break;
            case Key.D0 when ctrl:
                ActualSize();
                e.Handled = true;
                break;
            case Key.D9 when ctrl:
                ZoomToFit();
                e.Handled = true;
                break;

            // Navigation
            case Key.Down when ctrl:
                Project.SelectNextVideo();
                e.Handled = true;
                break;
            case Key.Up when ctrl:
                Project.SelectPreviousVideo();
                e.Handled = true;
                break;
            case Key.Delete when ctrl:
                Project.RemoveSelectedVideo();
                e.Handled = true;
                break;

            // Copy/Paste crop settings
            case Key.C when ctrl && !shift:
                CopyCropSettings();
                e.Handled = true;
                break;
            case Key.V when ctrl && !shift:
                PasteCropSettings();
                e.Handled = true;
                break;

            // Export all
            case Key.E when ctrl && shift:
                _ = ExportAll();
                e.Handled = true;
                break;

            // Loop
            case Key.L when ctrl:
                Player.ToggleLoop();
                e.Handled = true;
                break;

            // Timeline
            case Key.B when ctrl:
                Timeline.SplitClipAtPlayhead();
                e.Handled = true;
                break;
            case Key.I when !ctrl:
                Timeline.SetInPoint();
                e.Handled = true;
                break;
            case Key.O when !ctrl:
                Timeline.SetOutPoint();
                e.Handled = true;
                break;
            case Key.T when ctrl && alt:
                Player.ToggleTimeDisplay();
                e.Handled = true;
                break;

            // Settings
            case Key.OemComma when ctrl:
                ShowSettings();
                e.Handled = true;
                break;
        }
    }
}
