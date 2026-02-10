using System.Collections.ObjectModel;
using System.Windows;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CropawayWindows.Models;
using CropawayWindows.Services;

namespace CropawayWindows.ViewModels;

public partial class KeyframeViewModel : ObservableObject
{
    [ObservableProperty]
    private ObservableCollection<Keyframe> _keyframes = new();

    [ObservableProperty]
    private bool _keyframesEnabled;

    [ObservableProperty]
    private Keyframe? _selectedKeyframe;

    [ObservableProperty]
    private bool _isTimelinePanelVisible;

    [ObservableProperty]
    private double _currentTime;

    private VideoItem? _currentVideo;
    private CropEditorViewModel? _cropEditor;
    private VideoPlayerViewModel? _playerVM;

    public void Initialize(CropEditorViewModel cropEditor, VideoPlayerViewModel playerVM)
    {
        _cropEditor = cropEditor;
        _playerVM = playerVM;

        // Auto-keyframe: when crop edit ends, update current keyframe
        cropEditor.CropEditEnded += OnCropEditEnded;
    }

    public void BindTo(VideoItem video)
    {
        _currentVideo = video;
        var config = video.CropConfig;

        Keyframes = new ObservableCollection<Keyframe>(config.Keyframes);
        KeyframesEnabled = config.KeyframesEnabled;
    }

    public void UpdateCurrentTime(double time)
    {
        CurrentTime = time;

        // Apply interpolation if keyframes are enabled
        if (KeyframesEnabled && Keyframes.Count > 1 && _cropEditor != null && _currentVideo != null)
        {
            var keyframeData = Keyframes.Select(ToKeyframeData).ToList();
            var state = KeyframeInterpolator.Instance.Interpolate(
                keyframeData,
                time,
                _cropEditor.Mode);

            // Apply interpolated state to editor (without triggering sync back)
            _cropEditor.CropRect = state.CropRect;
            _cropEditor.CircleCenter = state.CircleCenter;
            _cropEditor.CircleRadius = state.CircleRadius;
            if (state.AIBoundingBox.Width > 0)
                _cropEditor.AiBoundingBox = state.AIBoundingBox;
        }

        // Highlight current keyframe
        SelectedKeyframe = Keyframes.FirstOrDefault(kf => Math.Abs(kf.Timestamp - time) < 0.001);
    }

    [RelayCommand]
    public void AddKeyframe()
    {
        if (_currentVideo == null || _cropEditor == null) return;

        var config = _currentVideo.CropConfig;
        config.AddKeyframe(CurrentTime);
        Keyframes = new ObservableCollection<Keyframe>(config.Keyframes);

        if (!KeyframesEnabled && Keyframes.Count >= 2)
        {
            KeyframesEnabled = true;
            config.KeyframesEnabled = true;
        }
    }

    [RelayCommand]
    public void RemoveKeyframe()
    {
        if (_currentVideo == null) return;

        var config = _currentVideo.CropConfig;
        config.RemoveKeyframe(CurrentTime);
        Keyframes = new ObservableCollection<Keyframe>(config.Keyframes);

        if (Keyframes.Count < 2)
        {
            KeyframesEnabled = false;
            config.KeyframesEnabled = false;
        }
    }

    [RelayCommand]
    public void GoToPreviousKeyframe()
    {
        var prev = Keyframes
            .Where(kf => kf.Timestamp < CurrentTime - 0.01)
            .OrderByDescending(kf => kf.Timestamp)
            .FirstOrDefault();

        if (prev != null)
        {
            _playerVM?.Seek(prev.Timestamp);
        }
    }

    [RelayCommand]
    public void GoToNextKeyframe()
    {
        var next = Keyframes
            .Where(kf => kf.Timestamp > CurrentTime + 0.01)
            .OrderBy(kf => kf.Timestamp)
            .FirstOrDefault();

        if (next != null)
        {
            _playerVM?.Seek(next.Timestamp);
        }
    }

    [RelayCommand]
    public void ToggleKeyframePanel()
    {
        IsTimelinePanelVisible = !IsTimelinePanelVisible;
    }

    public void SetInterpolation(Keyframe keyframe, KeyframeInterpolation interpolation)
    {
        keyframe.Interpolation = interpolation;
    }

    private void OnCropEditEnded()
    {
        if (_currentVideo == null || !KeyframesEnabled) return;

        // Auto-update keyframe at current time if one exists
        var config = _currentVideo.CropConfig;
        config.UpdateCurrentKeyframe(CurrentTime);
    }

    public bool IsAtKeyframe => Keyframes.Any(kf => Math.Abs(kf.Timestamp - CurrentTime) < 0.001);

    /// <summary>
    /// Converts a Keyframe model object to a KeyframeData service object for interpolation.
    /// </summary>
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

    /// <summary>
    /// Imports AI tracking results as keyframes, sampling bounding boxes at regular intervals.
    /// </summary>
    public void ImportAITrackingResults(Dictionary<int, System.Windows.Rect> frameBoundingBoxes, double frameRate)
    {
        if (_currentVideo == null || _cropEditor == null || frameBoundingBoxes.Count == 0) return;

        var config = _currentVideo.CropConfig;

        // Determine sample interval (aim for ~30-50 keyframes max)
        int totalFrames = frameBoundingBoxes.Keys.Max() + 1;
        int sampleInterval = Math.Max(1, totalFrames / 40);

        foreach (var (frameIndex, bbox) in frameBoundingBoxes.OrderBy(kv => kv.Key))
        {
            if (frameIndex % sampleInterval != 0 && frameIndex != 0) continue;

            double timestamp = frameRate > 0 ? frameIndex / frameRate : frameIndex * (1.0 / 30.0);

            // Set AI bounding box on the config temporarily
            config.AiBoundingBox = bbox;
            config.AddKeyframe(timestamp);
        }

        // Refresh keyframes from config
        Keyframes = new System.Collections.ObjectModel.ObservableCollection<Models.Keyframe>(config.Keyframes);

        if (Keyframes.Count >= 2)
        {
            KeyframesEnabled = true;
            config.KeyframesEnabled = true;
        }
    }
}
