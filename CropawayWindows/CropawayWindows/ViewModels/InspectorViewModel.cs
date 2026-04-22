// InspectorViewModel.cs
// CropawayWindows

using System.ComponentModel;
using System.Windows;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CropawayWindows.Models;

namespace CropawayWindows.ViewModels;

/// <summary>
/// ViewModel for the Inspector panel. Exposes editable crop coordinates,
/// transform settings, and audio metadata for the currently selected video.
/// Two-way binding for editable fields pushes changes back through CropEditorViewModel.
/// </summary>
public partial class InspectorViewModel : ObservableObject
{
    private CropEditorViewModel? _cropEditor;
    private VideoItem? _currentVideo;
    private bool _isSyncing;

    [ObservableProperty]
    private bool _isVisible;

    // -- Crop Inspector: Rectangle --
    [ObservableProperty]
    private double _rectX;

    [ObservableProperty]
    private double _rectY;

    [ObservableProperty]
    private double _rectWidth = 1.0;

    [ObservableProperty]
    private double _rectHeight = 1.0;

    // -- Crop Inspector: Circle --
    [ObservableProperty]
    private double _circleCenterX = 0.5;

    [ObservableProperty]
    private double _circleCenterY = 0.5;

    [ObservableProperty]
    private double _circleRadius = 0.4;

    // -- Crop Inspector: Freehand --
    [ObservableProperty]
    private int _freehandVertexCount;

    // -- Crop Inspector: AI --
    [ObservableProperty]
    private double _aiBboxX;

    [ObservableProperty]
    private double _aiBboxY;

    [ObservableProperty]
    private double _aiBboxWidth;

    [ObservableProperty]
    private double _aiBboxHeight;

    [ObservableProperty]
    private double _aiConfidence;

    [ObservableProperty]
    private string? _aiTextPrompt;

    // -- Crop mode --
    [ObservableProperty]
    private CropMode _cropMode = CropMode.Rectangle;

    [ObservableProperty]
    private string _cropModeDisplay = "Rectangle";

    // -- Transform Inspector --
    [ObservableProperty]
    private bool _preserveWidth = true;

    [ObservableProperty]
    private bool _enableAlphaChannel;

    [ObservableProperty]
    private int _outputWidth;

    [ObservableProperty]
    private int _outputHeight;

    [ObservableProperty]
    private string _outputDimensionsDisplay = "N/A";

    // -- Audio Inspector --
    [ObservableProperty]
    private string _audioCodec = "N/A";

    [ObservableProperty]
    private string _audioSampleRate = "N/A";

    [ObservableProperty]
    private string _audioChannels = "N/A";

    [ObservableProperty]
    private string _audioBitRate = "N/A";

    [ObservableProperty]
    private bool _hasAudio;

    // -- Video info for computed output --
    private int _videoWidth;
    private int _videoHeight;

    /// <summary>
    /// Initializes the inspector with a reference to the crop editor.
    /// Subscribes to property changes on the crop editor to keep in sync.
    /// </summary>
    public void Initialize(CropEditorViewModel cropEditor)
    {
        // Unsubscribe from previous editor if any
        if (_cropEditor != null)
            _cropEditor.PropertyChanged -= OnCropEditorPropertyChanged;

        _cropEditor = cropEditor;
        _cropEditor.PropertyChanged += OnCropEditorPropertyChanged;
    }

    /// <summary>
    /// Binds the inspector to the currently selected video item.
    /// Loads metadata for audio section and syncs crop values.
    /// </summary>
    public void BindTo(VideoItem? video)
    {
        _currentVideo = video;

        if (video == null)
        {
            ResetToDefaults();
            return;
        }

        _videoWidth = video.Metadata.Width;
        _videoHeight = video.Metadata.Height;

        // Load audio metadata
        LoadAudioMetadata(video.Metadata);

        // Sync from crop editor
        SyncFromCropEditor();
    }

    private void LoadAudioMetadata(VideoMetadata metadata)
    {
        HasAudio = metadata.HasAudio;

        if (metadata.HasAudio)
        {
            AudioCodec = metadata.AudioCodec ?? "Unknown";

            AudioSampleRate = metadata.AudioSampleRate.HasValue
                ? $"{metadata.AudioSampleRate.Value:N0} Hz"
                : "Unknown";

            AudioChannels = metadata.AudioChannels.HasValue
                ? metadata.AudioChannels.Value switch
                {
                    1 => "1 (Mono)",
                    2 => "2 (Stereo)",
                    6 => "6 (5.1 Surround)",
                    8 => "8 (7.1 Surround)",
                    _ => metadata.AudioChannels.Value.ToString()
                }
                : "Unknown";

            AudioBitRate = metadata.AudioBitRate.HasValue
                ? FormatBitRate(metadata.AudioBitRate.Value)
                : "Unknown";
        }
        else
        {
            AudioCodec = "No audio";
            AudioSampleRate = "N/A";
            AudioChannels = "N/A";
            AudioBitRate = "N/A";
        }
    }

    private static string FormatBitRate(long bitsPerSecond)
    {
        double kbps = bitsPerSecond / 1000.0;
        return kbps >= 1000
            ? $"{kbps / 1000.0:F1} Mbps"
            : $"{kbps:F0} Kbps";
    }

    /// <summary>
    /// Syncs all inspector fields from the current CropEditorViewModel state.
    /// </summary>
    private void SyncFromCropEditor()
    {
        if (_cropEditor == null) return;

        _isSyncing = true;

        CropMode = _cropEditor.Mode;
        CropModeDisplay = _cropEditor.Mode switch
        {
            CropMode.Rectangle => "Rectangle",
            CropMode.Circle => "Circle",
            CropMode.Freehand => "Custom Mask",
            CropMode.AI => "AI Track",
            _ => "Unknown"
        };

        // Rectangle
        RectX = Math.Round(_cropEditor.CropRect.X, 4);
        RectY = Math.Round(_cropEditor.CropRect.Y, 4);
        RectWidth = Math.Round(_cropEditor.CropRect.Width, 4);
        RectHeight = Math.Round(_cropEditor.CropRect.Height, 4);

        // Circle
        CircleCenterX = Math.Round(_cropEditor.CircleCenter.X, 4);
        CircleCenterY = Math.Round(_cropEditor.CircleCenter.Y, 4);
        CircleRadius = Math.Round(_cropEditor.CircleRadius, 4);

        // Freehand
        FreehandVertexCount = _cropEditor.FreehandPoints.Count;

        // AI
        AiBboxX = Math.Round(_cropEditor.AiBoundingBox.X, 4);
        AiBboxY = Math.Round(_cropEditor.AiBoundingBox.Y, 4);
        AiBboxWidth = Math.Round(_cropEditor.AiBoundingBox.Width, 4);
        AiBboxHeight = Math.Round(_cropEditor.AiBoundingBox.Height, 4);
        AiConfidence = _currentVideo?.CropConfig.AiConfidence ?? 0;
        AiTextPrompt = _cropEditor.AiTextPrompt;

        // Transform
        PreserveWidth = _cropEditor.PreserveWidth;
        EnableAlphaChannel = _cropEditor.EnableAlphaChannel;

        // Compute output dimensions
        UpdateOutputDimensions();

        _isSyncing = false;
    }

    /// <summary>
    /// Computes the output pixel dimensions based on the effective crop rect
    /// and the video's actual dimensions.
    /// </summary>
    private void UpdateOutputDimensions()
    {
        if (_cropEditor == null || _videoWidth <= 0 || _videoHeight <= 0)
        {
            OutputWidth = 0;
            OutputHeight = 0;
            OutputDimensionsDisplay = "N/A";
            return;
        }

        var effectiveRect = _cropEditor.EffectiveCropRect;
        int cropW = (int)Math.Round(effectiveRect.Width * _videoWidth);
        int cropH = (int)Math.Round(effectiveRect.Height * _videoHeight);

        // Ensure even dimensions for FFmpeg
        cropW = Math.Max(2, cropW - (cropW % 2));
        cropH = Math.Max(2, cropH - (cropH % 2));

        if (PreserveWidth)
        {
            OutputWidth = _videoWidth;
            // When preserving width, height is scaled proportionally
            double scaleRatio = (double)_videoWidth / cropW;
            OutputHeight = (int)Math.Round(cropH * scaleRatio);
            OutputHeight = Math.Max(2, OutputHeight - (OutputHeight % 2));
        }
        else
        {
            OutputWidth = cropW;
            OutputHeight = cropH;
        }

        OutputDimensionsDisplay = $"{OutputWidth} x {OutputHeight}";
    }

    private void ResetToDefaults()
    {
        _isSyncing = true;

        CropMode = CropMode.Rectangle;
        CropModeDisplay = "Rectangle";
        RectX = 0;
        RectY = 0;
        RectWidth = 1;
        RectHeight = 1;
        CircleCenterX = 0.5;
        CircleCenterY = 0.5;
        CircleRadius = 0.4;
        FreehandVertexCount = 0;
        AiBboxX = 0;
        AiBboxY = 0;
        AiBboxWidth = 0;
        AiBboxHeight = 0;
        AiConfidence = 0;
        AiTextPrompt = null;
        PreserveWidth = true;
        EnableAlphaChannel = false;
        OutputWidth = 0;
        OutputHeight = 0;
        OutputDimensionsDisplay = "N/A";
        AudioCodec = "N/A";
        AudioSampleRate = "N/A";
        AudioChannels = "N/A";
        AudioBitRate = "N/A";
        HasAudio = false;

        _isSyncing = false;
    }

    // -- Property change handlers: push edits back to CropEditor --

    partial void OnRectXChanged(double value)
    {
        if (_isSyncing || _cropEditor == null) return;
        var r = _cropEditor.CropRect;
        double clampedX = Math.Clamp(value, 0, 1 - r.Width);
        _cropEditor.CropRect = new Rect(clampedX, r.Y, r.Width, r.Height);
        UpdateOutputDimensions();
    }

    partial void OnRectYChanged(double value)
    {
        if (_isSyncing || _cropEditor == null) return;
        var r = _cropEditor.CropRect;
        double clampedY = Math.Clamp(value, 0, 1 - r.Height);
        _cropEditor.CropRect = new Rect(r.X, clampedY, r.Width, r.Height);
        UpdateOutputDimensions();
    }

    partial void OnRectWidthChanged(double value)
    {
        if (_isSyncing || _cropEditor == null) return;
        var r = _cropEditor.CropRect;
        double clampedW = Math.Clamp(value, 0.01, 1 - r.X);
        _cropEditor.CropRect = new Rect(r.X, r.Y, clampedW, r.Height);
        UpdateOutputDimensions();
    }

    partial void OnRectHeightChanged(double value)
    {
        if (_isSyncing || _cropEditor == null) return;
        var r = _cropEditor.CropRect;
        double clampedH = Math.Clamp(value, 0.01, 1 - r.Y);
        _cropEditor.CropRect = new Rect(r.X, r.Y, r.Width, clampedH);
        UpdateOutputDimensions();
    }

    partial void OnCircleCenterXChanged(double value)
    {
        if (_isSyncing || _cropEditor == null) return;
        double clamped = Math.Clamp(value, 0, 1);
        _cropEditor.CircleCenter = new Point(clamped, _cropEditor.CircleCenter.Y);
        UpdateOutputDimensions();
    }

    partial void OnCircleCenterYChanged(double value)
    {
        if (_isSyncing || _cropEditor == null) return;
        double clamped = Math.Clamp(value, 0, 1);
        _cropEditor.CircleCenter = new Point(_cropEditor.CircleCenter.X, clamped);
        UpdateOutputDimensions();
    }

    partial void OnCircleRadiusChanged(double value)
    {
        if (_isSyncing || _cropEditor == null) return;
        double clamped = Math.Clamp(value, 0.01, 0.5);
        _cropEditor.CircleRadius = clamped;
        UpdateOutputDimensions();
    }

    partial void OnPreserveWidthChanged(bool value)
    {
        if (_isSyncing || _cropEditor == null) return;
        _cropEditor.PreserveWidth = value;
        UpdateOutputDimensions();
    }

    partial void OnEnableAlphaChannelChanged(bool value)
    {
        if (_isSyncing || _cropEditor == null) return;
        _cropEditor.EnableAlphaChannel = value;
    }

    /// <summary>
    /// Responds to property changes on the CropEditorViewModel to keep
    /// the inspector fields in sync when crop changes come from elsewhere
    /// (e.g., drag on overlay, nudge keys, undo/redo).
    /// </summary>
    private void OnCropEditorPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (_isSyncing) return;

        switch (e.PropertyName)
        {
            case nameof(CropEditorViewModel.Mode):
            case nameof(CropEditorViewModel.CropRect):
            case nameof(CropEditorViewModel.CircleCenter):
            case nameof(CropEditorViewModel.CircleRadius):
            case nameof(CropEditorViewModel.FreehandPoints):
            case nameof(CropEditorViewModel.AiBoundingBox):
            case nameof(CropEditorViewModel.AiTextPrompt):
            case nameof(CropEditorViewModel.PreserveWidth):
            case nameof(CropEditorViewModel.EnableAlphaChannel):
                SyncFromCropEditor();
                break;
        }
    }

    // -- Commands --

    [RelayCommand]
    private void ToggleVisibility() => IsVisible = !IsVisible;

    [RelayCommand]
    private void ClearFreehand()
    {
        _cropEditor?.ClearFreehandCommand.Execute(null);
        FreehandVertexCount = 0;
    }
}
