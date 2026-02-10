using System.Windows;
using CommunityToolkit.Mvvm.ComponentModel;
using CropawayWindows.Models;

namespace CropawayWindows.ViewModels;

/// <summary>
/// Manages undo/redo for crop operations on a per-video basis.
/// </summary>
public partial class CropUndoManager : ObservableObject
{
    private readonly Stack<CropSnapshot> _undoStack = new();
    private readonly Stack<CropSnapshot> _redoStack = new();
    private const int MaxUndoLevels = 50;

    [ObservableProperty]
    private bool _canUndo;

    [ObservableProperty]
    private bool _canRedo;

    private VideoItem? _currentVideo;
    private bool _isApplying;

    public void BindTo(VideoItem video)
    {
        _currentVideo = video;
        _undoStack.Clear();
        _redoStack.Clear();
        UpdateState();

        // Save initial state
        SaveState();
    }

    /// <summary>
    /// Save current crop state for undo. Call this before making changes.
    /// </summary>
    public void SaveState()
    {
        if (_currentVideo == null || _isApplying) return;

        var snapshot = CaptureSnapshot(_currentVideo.CropConfig);
        _undoStack.Push(snapshot);
        _redoStack.Clear();

        // Limit stack size
        if (_undoStack.Count > MaxUndoLevels)
        {
            var items = _undoStack.ToArray();
            _undoStack.Clear();
            for (int i = 0; i < MaxUndoLevels; i++)
            {
                _undoStack.Push(items[MaxUndoLevels - 1 - i]);
            }
        }

        UpdateState();
    }

    public void Undo()
    {
        if (!CanUndo || _currentVideo == null) return;

        // Save current state for redo
        var current = CaptureSnapshot(_currentVideo.CropConfig);
        _redoStack.Push(current);

        // Restore previous state
        var previous = _undoStack.Pop();
        ApplySnapshot(previous, _currentVideo.CropConfig);

        UpdateState();
    }

    public void Redo()
    {
        if (!CanRedo || _currentVideo == null) return;

        // Save current state for undo
        var current = CaptureSnapshot(_currentVideo.CropConfig);
        _undoStack.Push(current);

        // Restore next state
        var next = _redoStack.Pop();
        ApplySnapshot(next, _currentVideo.CropConfig);

        UpdateState();
    }

    private void UpdateState()
    {
        CanUndo = _undoStack.Count > 1; // > 1 because first item is initial state
        CanRedo = _redoStack.Count > 0;
    }

    private static CropSnapshot CaptureSnapshot(CropConfiguration config)
    {
        return new CropSnapshot
        {
            Mode = config.Mode,
            CropRect = config.CropRect,
            EdgeInsets = config.EdgeInsets,
            CircleCenter = config.CircleCenter,
            CircleRadius = config.CircleRadius,
            FreehandPoints = config.FreehandPoints.ToList(),
            FreehandPathData = config.FreehandPathData?.ToArray(),
            AIMaskData = config.AiMaskData?.ToArray(),
            AIPromptPoints = config.AiPromptPoints.ToList(),
            AITextPrompt = config.AiTextPrompt,
            AIBoundingBox = config.AiBoundingBox,
            PreserveWidth = config.PreserveWidth,
            EnableAlphaChannel = config.EnableAlphaChannel,
            KeyframesEnabled = config.KeyframesEnabled,
            Keyframes = config.Keyframes.Select(kf => kf.Copy()).ToList()
        };
    }

    private void ApplySnapshot(CropSnapshot snapshot, CropConfiguration config)
    {
        _isApplying = true;

        config.Mode = snapshot.Mode;
        config.CropRect = snapshot.CropRect;
        config.EdgeInsets = snapshot.EdgeInsets;
        config.CircleCenter = snapshot.CircleCenter;
        config.CircleRadius = snapshot.CircleRadius;
        config.FreehandPoints = snapshot.FreehandPoints.ToList();
        config.FreehandPathData = snapshot.FreehandPathData?.ToArray();
        config.AiMaskData = snapshot.AIMaskData?.ToArray();
        config.AiPromptPoints = snapshot.AIPromptPoints.ToList();
        config.AiTextPrompt = snapshot.AITextPrompt;
        config.AiBoundingBox = snapshot.AIBoundingBox;
        config.PreserveWidth = snapshot.PreserveWidth;
        config.EnableAlphaChannel = snapshot.EnableAlphaChannel;
        config.KeyframesEnabled = snapshot.KeyframesEnabled;
        config.Keyframes = new System.Collections.ObjectModel.ObservableCollection<Keyframe>(
            snapshot.Keyframes.Select(kf => kf.Copy()));

        _isApplying = false;
    }

    private class CropSnapshot
    {
        public CropMode Mode { get; set; }
        public Rect CropRect { get; set; }
        public Models.EdgeInsets EdgeInsets { get; set; } = new();
        public Point CircleCenter { get; set; }
        public double CircleRadius { get; set; }
        public List<Point> FreehandPoints { get; set; } = new();
        public byte[]? FreehandPathData { get; set; }
        public byte[]? AIMaskData { get; set; }
        public List<AIPromptPoint> AIPromptPoints { get; set; } = new();
        public string? AITextPrompt { get; set; }
        public Rect AIBoundingBox { get; set; }
        public bool PreserveWidth { get; set; }
        public bool EnableAlphaChannel { get; set; }
        public bool KeyframesEnabled { get; set; }
        public List<Keyframe> Keyframes { get; set; } = new();
    }
}
