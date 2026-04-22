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
    public InspectorViewModel Inspector { get; } = new();

    [ObservableProperty]
    private bool _isSidebarVisible = true;

    [ObservableProperty]
    private bool _isKeyframePanelVisible;

    [ObservableProperty]
    private bool _isTimelinePanelVisible;

    [ObservableProperty]
    private double _zoomLevel = 1.0;

    [ObservableProperty]
    private ZoomMode _zoomMode = ZoomMode.Fit;

    [ObservableProperty]
    private string _zoomDisplayText = "Fit";

    /// <summary>
    /// Preset zoom levels used for stepping through zoom in/out.
    /// </summary>
    private static readonly double[] ZoomPresets = { 0.25, 0.50, 0.75, 1.0, 1.5, 2.0, 3.0, 4.0 };

    [ObservableProperty]
    private string _statusBarText = "Ready - Drop videos here or use File > Open";

    [ObservableProperty]
    private bool _isFullScreen;

    [ObservableProperty]
    private bool _isAIPanelVisible;

    [ObservableProperty]
    private string _windowTitle = "Cropaway";

    // Auto-save debounce
    private CancellationTokenSource? _autoSaveCts;
    private const int AutoSaveDebounceMs = 500;

    // Copied crop configuration for paste
    private CropConfiguration? _copiedCropConfig;

    // Playback position memory: remembers where each video was last positioned (video path -> seconds)
    private readonly Dictionary<string, double> _videoPositions = new();

    // Track the previously selected video for saving its position on switch
    private VideoItem? _previousSelectedVideo;

    public MainViewModel()
    {
        // Wire up sub-ViewModels
        Keyframes.Initialize(CropEditor, Player);
        Timeline.Initialize(Player, Project);
        Inspector.Initialize(CropEditor);

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
        // and refresh export command CanExecute state
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
                ExportCurrentVideoCommand.NotifyCanExecuteChanged();
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
        if (video == null)
        {
            WindowTitle = "Cropaway";
            ExportCurrentVideoCommand.NotifyCanExecuteChanged();
            return;
        }

        // Save playback position of the previously selected video before switching
        if (_previousSelectedVideo != null && Player.Duration > 0)
        {
            _videoPositions[_previousSelectedVideo.SourcePath] = Player.CurrentTime;
        }

        // Bind all ViewModels to new video
        Player.LoadVideo(video);
        CropEditor.BindTo(video);
        Keyframes.BindTo(video);
        UndoManager.BindTo(video);
        Inspector.BindTo(video);

        // Restore playback position if we have a saved position for this video
        if (_videoPositions.TryGetValue(video.SourcePath, out var savedPosition))
        {
            // Defer seek slightly so MediaElement has time to open the new source
            Application.Current?.Dispatcher.InvokeAsync(() =>
            {
                Player.Seek(savedPosition);
            }, System.Windows.Threading.DispatcherPriority.Background);
        }

        _previousSelectedVideo = video;

        // Update window title with current video name
        WindowTitle = $"Cropaway - {video.FullFileName}";

        StatusBarText = $"{video.FileName} - {video.Metadata.Width}x{video.Metadata.Height} @ {video.Metadata.FrameRate:F2}fps";

        // Refresh export command CanExecute for the newly selected video
        ExportCurrentVideoCommand.NotifyCanExecuteChanged();
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
    private void ToggleInspector() => Inspector.IsVisible = !Inspector.IsVisible;

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
        if (ZoomMode == ZoomMode.Fit)
        {
            // When in fit mode, jump to 100% as the first zoom-in step
            SetZoomPercentage(1.0);
            return;
        }

        // Find the next preset level above the current zoom
        foreach (var preset in ZoomPresets)
        {
            if (preset > ZoomLevel + 0.001)
            {
                SetZoomPercentage(preset);
                return;
            }
        }

        // Already at or above max preset
    }

    [RelayCommand]
    private void ZoomOut()
    {
        if (ZoomMode == ZoomMode.Fit)
        {
            // When in fit mode, jump to 75% as the first zoom-out step
            SetZoomPercentage(0.75);
            return;
        }

        // Find the next preset level below the current zoom
        for (int i = ZoomPresets.Length - 1; i >= 0; i--)
        {
            if (ZoomPresets[i] < ZoomLevel - 0.001)
            {
                SetZoomPercentage(ZoomPresets[i]);
                return;
            }
        }

        // Already at or below min preset, go to fit
        ZoomToFit();
    }

    [RelayCommand]
    private void ZoomToFit()
    {
        ZoomMode = ZoomMode.Fit;
        ZoomLevel = 1.0;
        UpdateZoomDisplayText();
    }

    [RelayCommand]
    private void ActualSize()
    {
        SetZoomPercentage(1.0);
    }

    /// <summary>
    /// Sets the zoom to a specific percentage level (1.0 = 100%).
    /// Switches to Percentage mode and updates the display text.
    /// </summary>
    public void SetZoomPercentage(double level)
    {
        ZoomMode = ZoomMode.Percentage;
        ZoomLevel = Math.Clamp(level, ZoomPresets[0], ZoomPresets[^1]);
        UpdateZoomDisplayText();
    }

    /// <summary>
    /// Handles Ctrl+MouseWheel zoom: steps through preset levels based on scroll direction.
    /// </summary>
    public void HandleMouseWheelZoom(int delta)
    {
        if (delta > 0)
            ZoomIn();
        else if (delta < 0)
            ZoomOut();
    }

    private void UpdateZoomDisplayText()
    {
        if (ZoomMode == ZoomMode.Fit)
        {
            ZoomDisplayText = "Fit";
        }
        else
        {
            var pct = (int)Math.Round(ZoomLevel * 100);
            ZoomDisplayText = $"{pct}%";
        }
    }

    /// <summary>
    /// Returns true if the selected video has crop changes and can be exported.
    /// Used as CanExecute for ExportCurrentVideoCommand.
    /// </summary>
    private bool CanExportCurrentVideo() =>
        Project.SelectedVideo?.HasCropChanges == true;

    [RelayCommand(CanExecute = nameof(CanExportCurrentVideo))]
    private async Task ExportCurrentVideo()
    {
        if (Project.SelectedVideo != null)
        {
            UndoManager.SaveState();
            await Export.ExportVideo(Project.SelectedVideo);
        }
    }

    [RelayCommand]
    private void ExportBoundingBoxJson()
    {
        if (Project.SelectedVideo == null) return;

        // Ensure current crop state is synced to config before export
        SyncCropEditorToConfig();
        Export.ExportBoundingBoxJson(Project.SelectedVideo);
    }

    [RelayCommand]
    private void ExportBoundingBoxPickle()
    {
        if (Project.SelectedVideo == null) return;

        SyncCropEditorToConfig();
        Export.ExportBoundingBoxPickle(Project.SelectedVideo);
    }

    /// <summary>
    /// Explicitly sync current CropEditor state back to the video's CropConfiguration.
    /// Normally this happens via On*Changed partial methods, but calling this ensures
    /// all values are current before an export.
    /// </summary>
    private void SyncCropEditorToConfig()
    {
        var video = Project.SelectedVideo;
        if (video == null) return;

        var config = video.CropConfig;
        config.Mode = CropEditor.Mode;
        config.CropRect = CropEditor.CropRect;
        config.EdgeInsets = CropEditor.EdgeInsets;
        config.CircleCenter = CropEditor.CircleCenter;
        config.CircleRadius = CropEditor.CircleRadius;
        config.FreehandPoints = CropEditor.FreehandPoints.ToList();
        config.FreehandPathData = CropEditor.FreehandPathData;
        config.AiMaskData = CropEditor.AiMaskData;
        config.AiBoundingBox = CropEditor.AiBoundingBox;
        config.AiTextPrompt = CropEditor.AiTextPrompt;
        config.PreserveWidth = CropEditor.PreserveWidth;
        config.EnableAlphaChannel = CropEditor.EnableAlphaChannel;
    }

    [RelayCommand]
    private void ResetCrop()
    {
        UndoManager.SaveState();
        CropEditor.Reset();
        ExportCurrentVideoCommand.NotifyCanExecuteChanged();
    }

    [RelayCommand]
    private void NudgeCropLeft()
    {
        UndoManager.SaveState();
        CropEditor.NudgeCrop(-0.01, 0);
    }

    [RelayCommand]
    private void NudgeCropRight()
    {
        UndoManager.SaveState();
        CropEditor.NudgeCrop(0.01, 0);
    }

    [RelayCommand]
    private void NudgeCropUp()
    {
        UndoManager.SaveState();
        CropEditor.NudgeCrop(0, -0.01);
    }

    [RelayCommand]
    private void NudgeCropDown()
    {
        UndoManager.SaveState();
        CropEditor.NudgeCrop(0, 0.01);
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
    private void GoToPreviousKeyframe()
    {
        Keyframes.GoToPreviousKeyframe();
    }

    [RelayCommand]
    private void GoToNextKeyframe()
    {
        Keyframes.GoToNextKeyframe();
    }

    [RelayCommand]
    private void ToggleAutoKeyframe()
    {
        Keyframes.ToggleAutoKeyframe();
        StatusBarText = Keyframes.IsAutoKeyframeEnabled
            ? "Auto-Keyframe enabled"
            : "Auto-Keyframe disabled";
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

        // When Alt is held, WPF reports e.Key as Key.System; the actual key is in e.SystemKey
        var key = e.Key == Key.System ? e.SystemKey : e.Key;

        switch (key)
        {
            // Playback
            case Key.Space:
                Player.TogglePlayPause();
                e.Handled = true;
                break;

            // Jump forward/backward 10 seconds (Ctrl+Shift+Arrow)
            case Key.Right when ctrl && shift:
                Player.JumpForwardBy(10);
                e.Handled = true;
                break;
            case Key.Left when ctrl && shift:
                Player.JumpBackwardBy(10);
                e.Handled = true;
                break;

            // Jump forward/backward 1 second (Shift+Arrow)
            case Key.Right when !ctrl && shift:
                Player.JumpForwardBy(1);
                e.Handled = true;
                break;
            case Key.Left when !ctrl && shift:
                Player.JumpBackwardBy(1);
                e.Handled = true;
                break;

            // Crop nudge (Alt+Arrow)
            case Key.Right when alt && !ctrl && !shift:
                NudgeCropRight();
                e.Handled = true;
                break;
            case Key.Left when alt && !ctrl && !shift:
                NudgeCropLeft();
                e.Handled = true;
                break;
            case Key.Up when alt && !ctrl && !shift:
                NudgeCropUp();
                e.Handled = true;
                break;
            case Key.Down when alt && !ctrl && !shift:
                NudgeCropDown();
                e.Handled = true;
                break;

            // Step single frame (plain Arrow)
            case Key.Right when !ctrl && !shift && !alt:
                Player.StepForward();
                e.Handled = true;
                break;
            case Key.Left when !ctrl && !shift && !alt:
                Player.StepBackward();
                e.Handled = true;
                break;

            // Go to start/end (Home/End)
            case Key.Home:
                Player.GoToStart();
                e.Handled = true;
                break;
            case Key.End:
                Player.GoToEnd();
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

            // Playback speed presets (Ctrl+Alt+S/D/F)
            case Key.S when ctrl && alt:
                Player.SetSpeedSlow();
                e.Handled = true;
                break;
            case Key.D when ctrl && alt:
                Player.SetSpeedNormal();
                e.Handled = true;
                break;
            case Key.F when ctrl && alt:
                Player.SetSpeedFast();
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

            // Keyframe navigation
            case Key.OemOpenBrackets when ctrl && !shift:
                GoToPreviousKeyframe();
                e.Handled = true;
                break;
            case Key.OemCloseBrackets when ctrl && !shift:
                GoToNextKeyframe();
                e.Handled = true;
                break;

            // Auto-keyframe toggle
            case Key.A when ctrl && shift:
                ToggleAutoKeyframe();
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
                if (CanExportCurrentVideo())
                    _ = ExportCurrentVideo();
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
            case Key.OemBackslash when ctrl:
                ToggleSidebar();
                e.Handled = true;
                break;

            // Navigation
            case Key.Down when ctrl:
                Project.SelectNextVideoCommand.Execute(null);
                e.Handled = true;
                break;
            case Key.Up when ctrl:
                Project.SelectPreviousVideoCommand.Execute(null);
                e.Handled = true;
                break;
            case Key.Delete when ctrl:
                Project.RemoveSelectedVideoCommand.Execute(null);
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

            // Inspector panel
            case Key.I when ctrl && alt:
                ToggleInspector();
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
