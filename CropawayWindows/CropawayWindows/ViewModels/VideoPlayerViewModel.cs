using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CropawayWindows.Models;

namespace CropawayWindows.ViewModels;

public partial class VideoPlayerViewModel : ObservableObject
{
    [ObservableProperty]
    private double _currentTime;

    [ObservableProperty]
    private double _duration;

    [ObservableProperty]
    private double _frameRate = 30.0;

    [ObservableProperty]
    private bool _isPlaying;

    [ObservableProperty]
    private Size _videoSize;

    [ObservableProperty]
    private bool _isLooping;

    [ObservableProperty]
    private float _currentRate = 1.0f;

    [ObservableProperty]
    private bool _showFrameCount;

    [ObservableProperty]
    private VideoItem? _currentVideo;

    [ObservableProperty]
    private Uri? _mediaSource;

    // MediaElement reference will be set by the view
    private MediaElement? _mediaElement;
    private DispatcherTimer? _positionTimer;

    // Shuttle control state for J/K/L speed ramping
    private float _shuttleSpeed;
    private static readonly float[] ShuttleSpeeds = { 0.5f, 1.0f, 2.0f, 4.0f, 8.0f };

    public void SetMediaElement(MediaElement element)
    {
        _mediaElement = element;
        _mediaElement.MediaOpened += OnMediaOpened;
        _mediaElement.MediaEnded += OnMediaEnded;
        _mediaElement.LoadedBehavior = MediaState.Manual;
        _mediaElement.UnloadedBehavior = MediaState.Manual;
        _mediaElement.ScrubbingEnabled = true;

        // Timer for position updates
        _positionTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(33) // ~30fps updates
        };
        _positionTimer.Tick += OnPositionTimerTick;
    }

    public void LoadVideo(VideoItem video)
    {
        CurrentVideo = video;
        FrameRate = video.Metadata.FrameRate > 0 ? video.Metadata.FrameRate : 30.0;

        MediaSource = new Uri(video.SourcePath);
        _mediaElement?.Stop();

        // Duration will be set in OnMediaOpened
    }

    private void OnMediaOpened(object? sender, RoutedEventArgs e)
    {
        if (_mediaElement?.NaturalDuration.HasTimeSpan == true)
        {
            Duration = _mediaElement.NaturalDuration.TimeSpan.TotalSeconds;
        }

        if (_mediaElement != null)
        {
            VideoSize = new Size(
                _mediaElement.NaturalVideoWidth,
                _mediaElement.NaturalVideoHeight);
        }

        // Seek to first frame
        _mediaElement?.Pause();
        CurrentTime = 0;
    }

    private void OnMediaEnded(object? sender, RoutedEventArgs e)
    {
        IsPlaying = false;
        _positionTimer?.Stop();

        if (IsLooping)
        {
            Seek(0);
            Play();
        }
    }

    private void OnPositionTimerTick(object? sender, EventArgs e)
    {
        if (_mediaElement != null && IsPlaying)
        {
            CurrentTime = _mediaElement.Position.TotalSeconds;
        }
    }

    [RelayCommand]
    public void Play()
    {
        _mediaElement?.Play();
        IsPlaying = true;
        _positionTimer?.Start();
    }

    [RelayCommand]
    public void Pause()
    {
        _mediaElement?.Pause();
        IsPlaying = false;
        _positionTimer?.Stop();
        // Update position one more time
        if (_mediaElement != null)
            CurrentTime = _mediaElement.Position.TotalSeconds;
    }

    [RelayCommand]
    public void TogglePlayPause()
    {
        if (IsPlaying)
            Pause();
        else
            Play();
    }

    public void Seek(double time)
    {
        time = Math.Max(0, Math.Min(Duration, time));
        CurrentTime = time;
        if (_mediaElement != null)
        {
            _mediaElement.Position = TimeSpan.FromSeconds(time);
        }
    }

    [RelayCommand]
    public void StepForward()
    {
        if (FrameRate <= 0) return;
        var frameTime = 1.0 / FrameRate;
        Seek(CurrentTime + frameTime);
    }

    [RelayCommand]
    public void StepBackward()
    {
        if (FrameRate <= 0) return;
        var frameTime = 1.0 / FrameRate;
        Seek(CurrentTime - frameTime);
    }

    [RelayCommand]
    public void PlayReverse()
    {
        // WPF MediaElement doesn't natively support reverse playback
        // Simulate by stepping backward rapidly
        CurrentRate = -1.0f;
        _shuttleSpeed = -1.0f;
    }

    public void SetPlaybackRate(float rate)
    {
        if (_mediaElement != null)
        {
            _mediaElement.SpeedRatio = Math.Max(0.1, Math.Abs(rate));
        }
        CurrentRate = rate;
        _shuttleSpeed = rate;
    }

    // MARK: Shuttle Controls (J/K/L)

    [RelayCommand]
    public void ShuttleReverse()
    {
        if (_shuttleSpeed > 0)
        {
            _shuttleSpeed = 0;
            Pause();
        }
        else if (_shuttleSpeed == 0)
        {
            _shuttleSpeed = -1.0f;
            SetPlaybackRate(_shuttleSpeed);
            // For reverse, step backward in a timer
            Play();
        }
        else
        {
            var currentIndex = Array.IndexOf(ShuttleSpeeds, -_shuttleSpeed);
            if (currentIndex < 0) currentIndex = 0;
            var nextIndex = Math.Min(currentIndex + 1, ShuttleSpeeds.Length - 1);
            _shuttleSpeed = -ShuttleSpeeds[nextIndex];
            SetPlaybackRate(Math.Abs(_shuttleSpeed));
        }
        CurrentRate = _shuttleSpeed;
    }

    [RelayCommand]
    public void ShuttleStop()
    {
        _shuttleSpeed = 0;
        Pause();
        CurrentRate = 0;
    }

    [RelayCommand]
    public void ShuttleForward()
    {
        if (_shuttleSpeed < 0)
        {
            _shuttleSpeed = 0;
            Pause();
        }
        else if (_shuttleSpeed == 0)
        {
            _shuttleSpeed = 1.0f;
            SetPlaybackRate(_shuttleSpeed);
            Play();
        }
        else
        {
            var currentIndex = Array.IndexOf(ShuttleSpeeds, _shuttleSpeed);
            if (currentIndex < 0) currentIndex = 0;
            var nextIndex = Math.Min(currentIndex + 1, ShuttleSpeeds.Length - 1);
            _shuttleSpeed = ShuttleSpeeds[nextIndex];
            SetPlaybackRate(_shuttleSpeed);
        }
        CurrentRate = _shuttleSpeed;
    }

    // Navigation

    [RelayCommand]
    public void GoToStart() => Seek(0);

    [RelayCommand]
    public void GoToEnd() => Seek(Math.Max(0, Duration - 0.1));

    [RelayCommand]
    public void JumpForward() => Seek(Math.Min(Duration, CurrentTime + 5));

    [RelayCommand]
    public void JumpBackward() => Seek(Math.Max(0, CurrentTime - 5));

    [RelayCommand]
    public void ToggleLoop()
    {
        IsLooping = !IsLooping;
    }

    [RelayCommand]
    public void ToggleTimeDisplay()
    {
        ShowFrameCount = !ShowFrameCount;
    }

    // Display properties

    public string RateDisplayString
    {
        get
        {
            if (CurrentRate == 0 || CurrentRate == 1.0f) return "";
            if (CurrentRate == -1.0f) return "Reverse";
            if (CurrentRate < 0) return $"{-CurrentRate:F1}x Reverse";
            return $"{CurrentRate:F1}x";
        }
    }

    public int TotalFrameCount
    {
        get
        {
            if (Duration <= 0 || FrameRate <= 0) return 0;
            return Math.Max(1, (int)Math.Floor(Duration * FrameRate));
        }
    }

    public int CurrentFrameIndex
    {
        get
        {
            if (FrameRate <= 0) return 0;
            var frame = (int)Math.Floor(CurrentTime * FrameRate);
            return Math.Clamp(frame, 0, Math.Max(0, TotalFrameCount - 1));
        }
    }

    public string FrameDisplayString => $"{CurrentFrameIndex} / {Math.Max(0, TotalFrameCount - 1)}";

    public string TimecodeDisplayString
    {
        get
        {
            var current = FormatTimecode(CurrentTime, FrameRate);
            var total = FormatTimecode(Duration, FrameRate);
            return $"{current} / {total}";
        }
    }

    public string TimeDisplayString => ShowFrameCount ? FrameDisplayString : TimecodeDisplayString;

    private static string FormatTimecode(double seconds, double fps)
    {
        if (seconds < 0) seconds = 0;
        var h = (int)(seconds / 3600);
        var m = (int)((seconds % 3600) / 60);
        var s = (int)(seconds % 60);
        var f = fps > 0 ? (int)((seconds % 1) * fps) : 0;

        if (h > 0)
            return $"{h:D2}:{m:D2}:{s:D2}:{f:D2}";
        return $"{m:D2}:{s:D2}:{f:D2}";
    }

    partial void OnCurrentTimeChanged(double value)
    {
        OnPropertyChanged(nameof(TimeDisplayString));
        OnPropertyChanged(nameof(FrameDisplayString));
        OnPropertyChanged(nameof(TimecodeDisplayString));
        OnPropertyChanged(nameof(CurrentFrameIndex));
    }

    partial void OnCurrentRateChanged(float value)
    {
        OnPropertyChanged(nameof(RateDisplayString));
    }
}
