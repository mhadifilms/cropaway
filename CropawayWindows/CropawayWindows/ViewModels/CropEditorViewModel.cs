using System.Windows;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CropawayWindows.Models;

namespace CropawayWindows.ViewModels;

public partial class CropEditorViewModel : ObservableObject
{
    [ObservableProperty]
    private CropMode _mode = CropMode.Rectangle;

    [ObservableProperty]
    private bool _isEditing = true;

    // Rectangle crop (normalized 0-1)
    [ObservableProperty]
    private Rect _cropRect = new(0, 0, 1, 1);

    // Edge crop
    [ObservableProperty]
    private Models.EdgeInsets _edgeInsets = new();

    // Circle crop
    [ObservableProperty]
    private Point _circleCenter = new(0.5, 0.5);

    [ObservableProperty]
    private double _circleRadius = 0.4;

    // Freehand
    [ObservableProperty]
    private List<Point> _freehandPoints = new();

    [ObservableProperty]
    private byte[]? _freehandPathData;

    [ObservableProperty]
    private bool _isDrawing;

    // AI mask
    [ObservableProperty]
    private byte[]? _aiMaskData;

    [ObservableProperty]
    private List<AIPromptPoint> _aiPromptPoints = new();

    [ObservableProperty]
    private string? _aiTextPrompt;

    [ObservableProperty]
    private Rect _aiBoundingBox;

    [ObservableProperty]
    private AIInteractionMode _aiInteractionMode = AIInteractionMode.Point;

    // Export settings per video
    [ObservableProperty]
    private bool _preserveWidth = true;

    [ObservableProperty]
    private bool _enableAlphaChannel;

    // Active video
    private VideoItem? _currentVideo;
    private bool _isSyncing;

    // Callback for when crop editing ends (drag gesture completed)
    public event Action? CropEditEnded;

    public void BindTo(VideoItem video)
    {
        _currentVideo = video;
        var config = video.CropConfig;

        _isSyncing = true;
        Mode = config.Mode;
        CropRect = config.CropRect;
        EdgeInsets = config.EdgeInsets;
        CircleCenter = config.CircleCenter;
        CircleRadius = config.CircleRadius;
        FreehandPoints = config.FreehandPoints.ToList();
        FreehandPathData = config.FreehandPathData;
        AiMaskData = config.AiMaskData;
        AiPromptPoints = config.AiPromptPoints.ToList();
        AiTextPrompt = config.AiTextPrompt;
        AiBoundingBox = config.AiBoundingBox;
        AiInteractionMode = config.AiInteractionMode;
        PreserveWidth = config.PreserveWidth;
        EnableAlphaChannel = config.EnableAlphaChannel;
        _isSyncing = false;
    }

    // Sync changes back to CropConfiguration
    partial void OnModeChanged(CropMode value)
    {
        if (!_isSyncing && _currentVideo != null)
            _currentVideo.CropConfig.Mode = value;
    }

    partial void OnCropRectChanged(Rect value)
    {
        if (!_isSyncing && _currentVideo != null)
            _currentVideo.CropConfig.CropRect = value;
    }

    partial void OnCircleCenterChanged(Point value)
    {
        if (!_isSyncing && _currentVideo != null)
            _currentVideo.CropConfig.CircleCenter = value;
    }

    partial void OnCircleRadiusChanged(double value)
    {
        if (!_isSyncing && _currentVideo != null)
            _currentVideo.CropConfig.CircleRadius = value;
    }

    partial void OnFreehandPointsChanged(List<Point> value)
    {
        if (!_isSyncing && _currentVideo != null)
            _currentVideo.CropConfig.FreehandPoints = value;
    }

    partial void OnFreehandPathDataChanged(byte[]? value)
    {
        if (!_isSyncing && _currentVideo != null)
            _currentVideo.CropConfig.FreehandPathData = value;
    }

    partial void OnAiMaskDataChanged(byte[]? value)
    {
        if (!_isSyncing && _currentVideo != null)
            _currentVideo.CropConfig.AiMaskData = value;
    }

    partial void OnAiBoundingBoxChanged(Rect value)
    {
        if (!_isSyncing && _currentVideo != null)
            _currentVideo.CropConfig.AiBoundingBox = value;
    }

    partial void OnPreserveWidthChanged(bool value)
    {
        if (!_isSyncing && _currentVideo != null)
            _currentVideo.CropConfig.PreserveWidth = value;
    }

    partial void OnEnableAlphaChannelChanged(bool value)
    {
        if (!_isSyncing && _currentVideo != null)
            _currentVideo.CropConfig.EnableAlphaChannel = value;
    }

    // Get effective crop area for current mode
    public Rect EffectiveCropRect
    {
        get
        {
            return Mode switch
            {
                CropMode.Rectangle => CropRect,
                CropMode.Circle => new Rect(
                    CircleCenter.X - CircleRadius,
                    CircleCenter.Y - CircleRadius,
                    CircleRadius * 2,
                    CircleRadius * 2),
                CropMode.Freehand when FreehandPoints.Count > 0 => GetFreehandBounds(),
                CropMode.AI when AiBoundingBox.Width > 0 => AiBoundingBox,
                _ => new Rect(0, 0, 1, 1)
            };
        }
    }

    private Rect GetFreehandBounds()
    {
        if (FreehandPoints.Count == 0) return new Rect(0, 0, 1, 1);
        var minX = FreehandPoints.Min(p => p.X);
        var maxX = FreehandPoints.Max(p => p.X);
        var minY = FreehandPoints.Min(p => p.Y);
        var maxY = FreehandPoints.Max(p => p.Y);
        return new Rect(minX, minY, maxX - minX, maxY - minY);
    }

    [RelayCommand]
    public void Reset()
    {
        CropRect = new Rect(0, 0, 1, 1);
        EdgeInsets = new Models.EdgeInsets();
        CircleCenter = new Point(0.5, 0.5);
        CircleRadius = 0.4;
        FreehandPoints = new List<Point>();
        FreehandPathData = null;
        AiMaskData = null;
        AiPromptPoints = new List<AIPromptPoint>();
        AiTextPrompt = null;
        AiBoundingBox = default;

        if (_currentVideo != null)
        {
            _currentVideo.CropConfig.Reset();
        }
    }

    // Freehand drawing
    public void StartDrawing(Point point)
    {
        FreehandPoints = new List<Point> { point };
        IsDrawing = true;
    }

    public void ContinueDrawing(Point point)
    {
        if (!IsDrawing) return;
        var pts = FreehandPoints.ToList();
        pts.Add(point);
        FreehandPoints = pts;
    }

    public void EndDrawing()
    {
        IsDrawing = false;
        if (FreehandPoints.Count > 2)
        {
            var first = FreehandPoints[0];
            var last = FreehandPoints[^1];
            var distance = Math.Sqrt(Math.Pow(first.X - last.X, 2) + Math.Pow(first.Y - last.Y, 2));
            if (distance > 0.01)
            {
                var pts = FreehandPoints.ToList();
                pts.Add(first);
                FreehandPoints = pts;
            }
        }
    }

    [RelayCommand]
    public void ClearFreehand()
    {
        FreehandPoints = new List<Point>();
        FreehandPathData = null;
    }

    [RelayCommand]
    public void ClearAIMask()
    {
        AiMaskData = null;
        AiPromptPoints = new List<AIPromptPoint>();
        AiTextPrompt = null;
        AiBoundingBox = default;
    }

    public void NotifyCropEditEnded()
    {
        CropEditEnded?.Invoke();
    }

    [RelayCommand]
    private void SetRectangleMode() => Mode = CropMode.Rectangle;

    [RelayCommand]
    private void SetCircleMode() => Mode = CropMode.Circle;

    [RelayCommand]
    private void SetFreehandMode() => Mode = CropMode.Freehand;

    [RelayCommand]
    private void SetAIMode() => Mode = CropMode.AI;
}
