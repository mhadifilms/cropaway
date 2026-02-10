using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CropawayWindows.Models;

namespace CropawayWindows.ViewModels;

public partial class TimelineViewModel : ObservableObject
{
    [ObservableProperty]
    private Timeline? _activeTimeline;

    [ObservableProperty]
    private ObservableCollection<Timeline> _timelines = new();

    [ObservableProperty]
    private TimelineClip? _selectedClip;

    [ObservableProperty]
    private int? _selectedClipIndex;

    [ObservableProperty]
    private double _playheadTime;

    [ObservableProperty]
    private bool _isTimelinePanelVisible;

    [ObservableProperty]
    private double _zoomLevel = 1.0;

    private VideoPlayerViewModel? _playerVM;
    private ProjectViewModel? _projectVM;

    public void Initialize(VideoPlayerViewModel playerVM, ProjectViewModel projectVM)
    {
        _playerVM = playerVM;
        _projectVM = projectVM;
    }

    [RelayCommand]
    public void CreateTimeline()
    {
        var timeline = new Timeline
        {
            Id = Guid.NewGuid(),
            Name = $"Sequence {Timelines.Count + 1}"
        };

        Timelines.Add(timeline);
        ActiveTimeline = timeline;
        IsTimelinePanelVisible = true;
    }

    [RelayCommand]
    public void ToggleTimelinePanel()
    {
        IsTimelinePanelVisible = !IsTimelinePanelVisible;
    }

    public void AddClipFromVideo(VideoItem video)
    {
        if (ActiveTimeline == null)
        {
            CreateTimeline();
        }

        var clip = new TimelineClip(video, inPoint: 0, outPoint: 1);

        ActiveTimeline!.AddClip(clip);
        SelectedClip = clip;
        SelectedClipIndex = ActiveTimeline.Clips.Count - 1;
    }

    [RelayCommand]
    public void RemoveSelectedClip()
    {
        if (ActiveTimeline == null || SelectedClip == null) return;

        var index = ActiveTimeline.Clips.IndexOf(SelectedClip);
        ActiveTimeline.RemoveClip(SelectedClip);

        if (ActiveTimeline.Clips.Count > 0)
        {
            var newIndex = Math.Min(index, ActiveTimeline.Clips.Count - 1);
            SelectedClip = ActiveTimeline.Clips[newIndex];
            SelectedClipIndex = newIndex;
        }
        else
        {
            SelectedClip = null;
            SelectedClipIndex = null;
        }
    }

    [RelayCommand]
    public void SplitClipAtPlayhead()
    {
        if (ActiveTimeline == null || SelectedClipIndex == null) return;

        var clip = ActiveTimeline.Clips[SelectedClipIndex.Value];
        var timelineClipStart = ActiveTimeline.GetClipStartTime(SelectedClipIndex.Value);
        var timeInClip = PlayheadTime - timelineClipStart;

        if (timeInClip > 0 && timeInClip < clip.TrimmedDuration)
        {
            ActiveTimeline.SplitClip(SelectedClipIndex.Value, timeInClip);
            OnPropertyChanged(nameof(ActiveTimeline));
        }
    }

    [RelayCommand]
    public void GoToNextClip()
    {
        if (ActiveTimeline == null || SelectedClipIndex == null) return;

        var nextIndex = SelectedClipIndex.Value + 1;
        if (nextIndex < ActiveTimeline.Clips.Count)
        {
            SelectedClipIndex = nextIndex;
            SelectedClip = ActiveTimeline.Clips[nextIndex];

            // Seek player to clip start
            var clipStart = ActiveTimeline.GetClipStartTime(nextIndex);
            _playerVM?.Seek(clipStart);
        }
    }

    [RelayCommand]
    public void GoToPreviousClip()
    {
        if (ActiveTimeline == null || SelectedClipIndex == null) return;

        var prevIndex = SelectedClipIndex.Value - 1;
        if (prevIndex >= 0)
        {
            SelectedClipIndex = prevIndex;
            SelectedClip = ActiveTimeline.Clips[prevIndex];

            var clipStart = ActiveTimeline.GetClipStartTime(prevIndex);
            _playerVM?.Seek(clipStart);
        }
    }

    public void Seek(double globalTime)
    {
        if (ActiveTimeline == null) return;

        var result = ActiveTimeline.GetClipAtTime(globalTime);
        if (result != null)
        {
            SelectedClipIndex = result.Value.ClipIndex;
            SelectedClip = result.Value.Clip;

            // Load the clip's video if different from current
            if (result.Value.Clip.VideoItem != null)
            {
                _playerVM?.LoadVideo(result.Value.Clip.VideoItem);
                _playerVM?.Seek(result.Value.TimeInClip);
            }
        }

        PlayheadTime = globalTime;
    }

    public void SetInPoint()
    {
        if (SelectedClip == null) return;

        var normalizedTime = _playerVM?.CurrentTime ?? 0;
        if (SelectedClip.SourceDuration > 0)
        {
            SelectedClip.InPoint = normalizedTime / SelectedClip.SourceDuration;
        }
    }

    public void SetOutPoint()
    {
        if (SelectedClip == null) return;

        var normalizedTime = _playerVM?.CurrentTime ?? 0;
        if (SelectedClip.SourceDuration > 0)
        {
            SelectedClip.OutPoint = normalizedTime / SelectedClip.SourceDuration;
        }
    }

    [RelayCommand]
    public void ZoomIn()
    {
        ZoomLevel = Math.Min(10.0, ZoomLevel * 1.25);
    }

    [RelayCommand]
    public void ZoomOut()
    {
        ZoomLevel = Math.Max(0.1, ZoomLevel / 1.25);
    }
}
