using System.Collections.Specialized;
using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using CropawayWindows.Models;
using CropawayWindows.ViewModels;

namespace CropawayWindows.Views;

public partial class KeyframeTimelineView : UserControl
{
    private const double KeyframeDiamondSize = 10;
    private const double TrackTopOffset = 30;
    private const double TrackHeight = 24;

    private KeyframeViewModel? ViewModel => DataContext as KeyframeViewModel;

    // Keep track of rendered keyframe markers for hit testing
    private readonly List<(Polygon shape, Keyframe keyframe)> _keyframeMarkers = new();

    public KeyframeTimelineView()
    {
        InitializeComponent();
        DataContextChanged += OnDataContextChanged;
    }

    private void OnDataContextChanged(object sender, DependencyPropertyChangedEventArgs e)
    {
        if (e.OldValue is KeyframeViewModel oldVM)
        {
            oldVM.PropertyChanged -= OnViewModelPropertyChanged;
            if (oldVM.Keyframes is INotifyCollectionChanged oldCollection)
            {
                oldCollection.CollectionChanged -= OnKeyframesCollectionChanged;
            }
        }

        if (e.NewValue is KeyframeViewModel newVM)
        {
            newVM.PropertyChanged += OnViewModelPropertyChanged;
            if (newVM.Keyframes is INotifyCollectionChanged newCollection)
            {
                newCollection.CollectionChanged += OnKeyframesCollectionChanged;
            }
            RedrawAll();
        }
    }

    private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        switch (e.PropertyName)
        {
            case nameof(KeyframeViewModel.CurrentTime):
                UpdatePlayhead();
                break;
            case nameof(KeyframeViewModel.Keyframes):
                // Rebind collection changed handler
                if (ViewModel?.Keyframes is INotifyCollectionChanged newCollection)
                {
                    newCollection.CollectionChanged += OnKeyframesCollectionChanged;
                }
                RedrawAll();
                break;
            case nameof(KeyframeViewModel.SelectedKeyframe):
                UpdateKeyframeSelection();
                break;
        }
    }

    private void OnKeyframesCollectionChanged(object? sender, NotifyCollectionChangedEventArgs e)
    {
        RedrawAll();
    }

    private void OnTimelineCanvasSizeChanged(object sender, SizeChangedEventArgs e)
    {
        RedrawAll();
    }

    /// <summary>
    /// Redraws all keyframe markers and updates the playhead position.
    /// </summary>
    private void RedrawAll()
    {
        if (TimelineCanvas == null || ViewModel == null) return;

        double canvasWidth = TimelineCanvas.ActualWidth;
        double canvasHeight = TimelineCanvas.ActualHeight;
        if (canvasWidth <= 0 || canvasHeight <= 0) return;

        // Update track bar width
        TrackBar.Width = canvasWidth;

        // Remove old keyframe markers
        foreach (var (shape, _) in _keyframeMarkers)
        {
            TimelineCanvas.Children.Remove(shape);
        }
        _keyframeMarkers.Clear();

        // Get video duration from player (traverse to MainViewModel)
        double duration = GetVideoDuration();
        if (duration <= 0) duration = 1.0;

        // Draw keyframe diamond markers
        var keyframeBrush = FindResource("KeyframeBrush") as SolidColorBrush
            ?? new SolidColorBrush(Color.FromRgb(0xFF, 0xB9, 0x00));
        var selectedBrush = FindResource("AccentBrush") as SolidColorBrush
            ?? new SolidColorBrush(Color.FromRgb(0x00, 0x78, 0xD4));

        foreach (var keyframe in ViewModel.Keyframes)
        {
            double normalizedX = keyframe.Timestamp / duration;
            double x = normalizedX * canvasWidth;
            double centerY = TrackTopOffset + TrackHeight / 2;

            // Create diamond shape
            var diamond = new Polygon
            {
                Points = new PointCollection
                {
                    new Point(x, centerY - KeyframeDiamondSize),
                    new Point(x + KeyframeDiamondSize, centerY),
                    new Point(x, centerY + KeyframeDiamondSize),
                    new Point(x - KeyframeDiamondSize, centerY)
                },
                Fill = (ViewModel.SelectedKeyframe?.Id == keyframe.Id)
                    ? selectedBrush
                    : keyframeBrush,
                Stroke = Brushes.Black,
                StrokeThickness = 0.5,
                Cursor = Cursors.Hand,
                ToolTip = $"{keyframe.Timestamp:F2}s - {keyframe.Interpolation.DisplayName()}"
            };

            // Click handler for selecting keyframe
            var kf = keyframe;
            diamond.MouseLeftButtonDown += (s, e) =>
            {
                e.Handled = true;
                OnKeyframeMarkerClicked(kf);
            };

            Canvas.SetZIndex(diamond, 10);
            TimelineCanvas.Children.Add(diamond);
            _keyframeMarkers.Add((diamond, keyframe));
        }

        UpdatePlayhead();
    }

    /// <summary>
    /// Updates the playhead vertical line position based on current time.
    /// </summary>
    private void UpdatePlayhead()
    {
        if (TimelineCanvas == null || ViewModel == null) return;

        double canvasWidth = TimelineCanvas.ActualWidth;
        double canvasHeight = TimelineCanvas.ActualHeight;
        if (canvasWidth <= 0) return;

        double duration = GetVideoDuration();
        if (duration <= 0) duration = 1.0;

        double normalizedX = ViewModel.CurrentTime / duration;
        double x = Math.Clamp(normalizedX * canvasWidth, 0, canvasWidth);

        PlayheadLine.X1 = x;
        PlayheadLine.X2 = x;
        PlayheadLine.Y1 = 0;
        PlayheadLine.Y2 = canvasHeight;
    }

    /// <summary>
    /// Updates the visual highlight state of keyframe markers based on selection.
    /// </summary>
    private void UpdateKeyframeSelection()
    {
        if (ViewModel == null) return;

        var keyframeBrush = FindResource("KeyframeBrush") as SolidColorBrush
            ?? new SolidColorBrush(Color.FromRgb(0xFF, 0xB9, 0x00));
        var selectedBrush = FindResource("AccentBrush") as SolidColorBrush
            ?? new SolidColorBrush(Color.FromRgb(0x00, 0x78, 0xD4));

        foreach (var (shape, keyframe) in _keyframeMarkers)
        {
            shape.Fill = (ViewModel.SelectedKeyframe?.Id == keyframe.Id)
                ? selectedBrush
                : keyframeBrush;
        }
    }

    /// <summary>
    /// When the user clicks on the timeline area (not a keyframe), seek to that time.
    /// </summary>
    private void OnTimelineCanvasClick(object sender, MouseButtonEventArgs e)
    {
        if (ViewModel == null) return;

        double canvasWidth = TimelineCanvas.ActualWidth;
        if (canvasWidth <= 0) return;

        double duration = GetVideoDuration();
        if (duration <= 0) return;

        Point clickPos = e.GetPosition(TimelineCanvas);
        double normalizedX = Math.Clamp(clickPos.X / canvasWidth, 0, 1);
        double seekTime = normalizedX * duration;

        // Navigate up to MainViewModel to seek the player
        var mainWindow = Window.GetWindow(this);
        var mainVM = mainWindow?.DataContext as MainViewModel;
        mainVM?.Player.Seek(seekTime);
    }

    /// <summary>
    /// When a keyframe diamond marker is clicked, select it and seek to its timestamp.
    /// </summary>
    private void OnKeyframeMarkerClicked(Keyframe keyframe)
    {
        if (ViewModel == null) return;

        ViewModel.SelectedKeyframe = keyframe;

        var mainWindow = Window.GetWindow(this);
        var mainVM = mainWindow?.DataContext as MainViewModel;
        mainVM?.Player.Seek(keyframe.Timestamp);
    }

    /// <summary>
    /// Mouse wheel over the keyframe timeline:
    /// - Ctrl+scroll: zoom the timeline in/out
    /// - Plain scroll: scroll the timeline horizontally (scrub through time)
    /// </summary>
    private void OnTimelineMouseWheel(object sender, MouseWheelEventArgs e)
    {
        if (ViewModel == null) return;

        bool ctrl = (Keyboard.Modifiers & ModifierKeys.Control) != 0;

        if (ctrl)
        {
            // Ctrl+scroll: zoom the keyframe timeline in/out
            double zoomDelta = e.Delta > 0 ? 0.25 : -0.25;
            double newZoom = Math.Clamp(ViewModel.TimelineZoomLevel + zoomDelta, 1.0, 10.0);
            ViewModel.TimelineZoomLevel = newZoom;

            // Clamp scroll offset when zooming out
            double maxOffset = Math.Max(0, 1.0 - (1.0 / newZoom));
            ViewModel.TimelineScrollOffset = Math.Clamp(ViewModel.TimelineScrollOffset, 0, maxOffset);

            RedrawAll();
        }
        else
        {
            // Plain scroll: horizontal pan through the timeline
            double duration = GetVideoDuration();
            if (duration <= 0) return;

            if (ViewModel.TimelineZoomLevel > 1.0)
            {
                // When zoomed in, scroll shifts the visible window
                double scrollStep = 0.05 / ViewModel.TimelineZoomLevel;
                double newOffset = ViewModel.TimelineScrollOffset + (e.Delta > 0 ? -scrollStep : scrollStep);
                double maxOffset = Math.Max(0, 1.0 - (1.0 / ViewModel.TimelineZoomLevel));
                ViewModel.TimelineScrollOffset = Math.Clamp(newOffset, 0, maxOffset);

                RedrawAll();
            }
            else
            {
                // When not zoomed in, scroll scrubs through time (seek)
                var mainWindow = Window.GetWindow(this);
                var mainVM = mainWindow?.DataContext as MainViewModel;
                if (mainVM != null)
                {
                    double seekStep = duration * 0.02; // 2% of duration per scroll tick
                    if (e.Delta > 0)
                        mainVM.Player.Seek(mainVM.Player.CurrentTime + seekStep);
                    else
                        mainVM.Player.Seek(mainVM.Player.CurrentTime - seekStep);
                }
            }
        }

        e.Handled = true;
    }

    /// <summary>
    /// Gets the total video duration by traversing to the MainViewModel's player.
    /// </summary>
    private double GetVideoDuration()
    {
        var mainWindow = Window.GetWindow(this);
        var mainVM = mainWindow?.DataContext as MainViewModel;
        return mainVM?.Player.Duration ?? 1.0;
    }
}
