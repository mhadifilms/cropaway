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

public partial class TimelineTrackView : UserControl
{
    private const double ClipHeight = 50;
    private const double ClipTopMargin = 12;
    private const double TrimHandleWidth = 6;
    private const double MinPixelsPerSecond = 40;

    private TimelineViewModel? ViewModel => DataContext as TimelineViewModel;

    // Rendered clip rectangles for hit testing and interaction
    private readonly List<ClipVisual> _clipVisuals = new();

    // Trim drag state
    private bool _isTrimming;
    private TrimEdge _trimEdge;
    private TimelineClip? _trimClip;
    private double _trimStartX;
    private double _trimOriginalValue;

    private enum TrimEdge { None, Left, Right }

    private class ClipVisual
    {
        public Border Container { get; init; } = null!;
        public TimelineClip Clip { get; init; } = null!;
        public double StartX { get; init; }
        public double Width { get; init; }
        public Rectangle? LeftHandle { get; init; }
        public Rectangle? RightHandle { get; init; }
    }

    public TimelineTrackView()
    {
        InitializeComponent();
        DataContextChanged += OnDataContextChanged;
    }

    private void OnDataContextChanged(object sender, DependencyPropertyChangedEventArgs e)
    {
        if (e.OldValue is TimelineViewModel oldVM)
        {
            oldVM.PropertyChanged -= OnViewModelPropertyChanged;
        }

        if (e.NewValue is TimelineViewModel newVM)
        {
            newVM.PropertyChanged += OnViewModelPropertyChanged;
            RedrawAll();
        }
    }

    private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        switch (e.PropertyName)
        {
            case nameof(TimelineViewModel.ActiveTimeline):
            case nameof(TimelineViewModel.ZoomLevel):
                if (ViewModel?.ActiveTimeline != null)
                {
                    ViewModel.ActiveTimeline.Clips.CollectionChanged -= OnClipsChanged;
                    ViewModel.ActiveTimeline.Clips.CollectionChanged += OnClipsChanged;
                }
                UpdateTimelineVisibility();
                RedrawAll();
                break;
            case nameof(TimelineViewModel.PlayheadTime):
                UpdatePlayhead();
                break;
            case nameof(TimelineViewModel.SelectedClip):
                UpdateClipSelection();
                break;
        }
    }

    /// <summary>
    /// Toggles between the empty state panel and the timeline scroller
    /// based on whether an active timeline exists.
    /// </summary>
    private void UpdateTimelineVisibility()
    {
        bool hasTimeline = ViewModel?.ActiveTimeline != null;
        EmptyTimelinePanel.Visibility = hasTimeline ? Visibility.Collapsed : Visibility.Visible;
        TimelineScroller.Visibility = hasTimeline ? Visibility.Visible : Visibility.Collapsed;
    }

    private void OnClipsChanged(object? sender, NotifyCollectionChangedEventArgs e)
    {
        RedrawAll();
    }

    private void OnTrackCanvasSizeChanged(object sender, SizeChangedEventArgs e)
    {
        RedrawAll();
    }

    /// <summary>
    /// Rebuilds all clip visuals on the canvas.
    /// </summary>
    private void RedrawAll()
    {
        if (TrackCanvas == null || ViewModel?.ActiveTimeline == null) return;

        // Clear old clip visuals
        foreach (var cv in _clipVisuals)
        {
            TrackCanvas.Children.Remove(cv.Container);
            if (cv.LeftHandle != null) TrackCanvas.Children.Remove(cv.LeftHandle);
            if (cv.RightHandle != null) TrackCanvas.Children.Remove(cv.RightHandle);
        }
        _clipVisuals.Clear();

        var timeline = ViewModel.ActiveTimeline;
        double totalDuration = timeline.TotalDuration;
        if (totalDuration <= 0) totalDuration = 1.0;

        double zoom = ViewModel.ZoomLevel;
        double pixelsPerSecond = Math.Max(MinPixelsPerSecond, (TrackCanvas.ActualWidth / totalDuration) * zoom);
        double totalWidth = totalDuration * pixelsPerSecond;

        TrackCanvas.Width = Math.Max(TrackCanvas.ActualWidth, totalWidth);

        var accentBrush = FindResource("AccentBrush") as SolidColorBrush
            ?? new SolidColorBrush(Color.FromRgb(0x00, 0x78, 0xD4));
        var borderBrush = FindResource("BorderBrush") as SolidColorBrush
            ?? new SolidColorBrush(Color.FromRgb(0x3F, 0x3F, 0x46));
        var surfaceBrush = FindResource("SurfaceBrush") as SolidColorBrush
            ?? new SolidColorBrush(Color.FromRgb(0x25, 0x25, 0x26));
        var textBrush = FindResource("TextPrimaryBrush") as SolidColorBrush
            ?? Brushes.White;
        var textSecondaryBrush = FindResource("TextSecondaryBrush") as SolidColorBrush
            ?? new SolidColorBrush(Color.FromRgb(0xA0, 0xA0, 0xA0));
        var handleBrush = FindResource("CropHandleBrush") as SolidColorBrush
            ?? new SolidColorBrush(Color.FromRgb(0x00, 0xB4, 0xFF));

        // Color palette for clips
        var clipColors = new[]
        {
            Color.FromRgb(0x26, 0x4F, 0x78),
            Color.FromRgb(0x4A, 0x3F, 0x6B),
            Color.FromRgb(0x3B, 0x5E, 0x4A),
            Color.FromRgb(0x6B, 0x4A, 0x3F),
            Color.FromRgb(0x3F, 0x5C, 0x6B),
        };

        double currentX = 0;

        for (int i = 0; i < timeline.Clips.Count; i++)
        {
            var clip = timeline.Clips[i];
            double clipDuration = clip.TrimmedDuration;
            double clipWidth = clipDuration * pixelsPerSecond;
            bool isSelected = (ViewModel.SelectedClip?.Id == clip.Id);

            // Clip background color
            var clipColor = clipColors[i % clipColors.Length];
            var clipBrush = new SolidColorBrush(clipColor);

            // Clip container border
            var clipBorder = new Border
            {
                Width = Math.Max(20, clipWidth),
                Height = ClipHeight,
                Background = clipBrush,
                BorderBrush = isSelected ? accentBrush : borderBrush,
                BorderThickness = new Thickness(isSelected ? 2 : 1),
                CornerRadius = new CornerRadius(3),
                ClipToBounds = true,
                Cursor = Cursors.Hand,
                ToolTip = $"{clip.DisplayName}\n" +
                          $"Duration: {clipDuration:F2}s\n" +
                          $"In: {clip.InPoint:P0} Out: {clip.OutPoint:P0}"
            };

            // Content inside clip
            var clipContent = new Grid();

            // Filmstrip color blocks (simplified filmstrip)
            var filmstrip = new StackPanel
            {
                Orientation = Orientation.Horizontal,
                IsHitTestVisible = false
            };
            int blockCount = Math.Max(1, (int)(clipWidth / 30));
            for (int b = 0; b < blockCount; b++)
            {
                double shade = 0.7 + (b % 2) * 0.1;
                var block = new Rectangle
                {
                    Width = clipWidth / blockCount,
                    Height = ClipHeight,
                    Fill = new SolidColorBrush(Color.FromScRgb(
                        0.3f,
                        (float)(clipColor.ScR * shade),
                        (float)(clipColor.ScG * shade),
                        (float)(clipColor.ScB * shade))),
                };
                filmstrip.Children.Add(block);
            }
            clipContent.Children.Add(filmstrip);

            // Clip label
            var label = new TextBlock
            {
                Text = clip.DisplayName,
                Foreground = textBrush,
                FontSize = 11,
                FontWeight = FontWeights.SemiBold,
                Margin = new Thickness(6, 4, 6, 0),
                TextTrimming = TextTrimming.CharacterEllipsis,
                IsHitTestVisible = false,
                VerticalAlignment = VerticalAlignment.Top
            };
            clipContent.Children.Add(label);

            // Duration label
            var durationLabel = new TextBlock
            {
                Text = FormatDuration(clipDuration),
                Foreground = textSecondaryBrush,
                FontSize = 9,
                Margin = new Thickness(6, 0, 6, 4),
                IsHitTestVisible = false,
                VerticalAlignment = VerticalAlignment.Bottom,
                HorizontalAlignment = System.Windows.HorizontalAlignment.Left
            };
            clipContent.Children.Add(durationLabel);

            clipBorder.Child = clipContent;

            // Position on canvas
            Canvas.SetLeft(clipBorder, currentX);
            Canvas.SetTop(clipBorder, ClipTopMargin);
            Canvas.SetZIndex(clipBorder, 1);
            TrackCanvas.Children.Add(clipBorder);

            // Click handler for clip selection
            int clipIndex = i;
            var capturedClip = clip;
            clipBorder.MouseLeftButtonDown += (s, e) =>
            {
                e.Handled = true;
                OnClipClicked(capturedClip, clipIndex);
            };

            // Context menu
            var contextMenu = CreateClipContextMenu(capturedClip, clipIndex);
            clipBorder.ContextMenu = contextMenu;

            // Trim handles
            Rectangle? leftHandle = null;
            Rectangle? rightHandle = null;

            if (isSelected)
            {
                // Left trim handle
                leftHandle = new Rectangle
                {
                    Width = TrimHandleWidth,
                    Height = ClipHeight,
                    Fill = handleBrush,
                    Cursor = Cursors.SizeWE,
                    Opacity = 0.8,
                    RadiusX = 2,
                    RadiusY = 2
                };
                Canvas.SetLeft(leftHandle, currentX);
                Canvas.SetTop(leftHandle, ClipTopMargin);
                Canvas.SetZIndex(leftHandle, 5);
                TrackCanvas.Children.Add(leftHandle);

                var leftClip = clip;
                leftHandle.MouseLeftButtonDown += (s, e) =>
                {
                    e.Handled = true;
                    StartTrimDrag(leftClip, TrimEdge.Left, e);
                };

                // Right trim handle
                rightHandle = new Rectangle
                {
                    Width = TrimHandleWidth,
                    Height = ClipHeight,
                    Fill = handleBrush,
                    Cursor = Cursors.SizeWE,
                    Opacity = 0.8,
                    RadiusX = 2,
                    RadiusY = 2
                };
                Canvas.SetLeft(rightHandle, currentX + clipWidth - TrimHandleWidth);
                Canvas.SetTop(rightHandle, ClipTopMargin);
                Canvas.SetZIndex(rightHandle, 5);
                TrackCanvas.Children.Add(rightHandle);

                var rightClip = clip;
                rightHandle.MouseLeftButtonDown += (s, e) =>
                {
                    e.Handled = true;
                    StartTrimDrag(rightClip, TrimEdge.Right, e);
                };
            }

            _clipVisuals.Add(new ClipVisual
            {
                Container = clipBorder,
                Clip = clip,
                StartX = currentX,
                Width = clipWidth,
                LeftHandle = leftHandle,
                RightHandle = rightHandle
            });

            currentX += clipWidth + 2; // Small gap between clips
        }

        UpdatePlayhead();
    }

    /// <summary>
    /// Updates the playhead line position.
    /// </summary>
    private void UpdatePlayhead()
    {
        if (TrackCanvas == null || ViewModel?.ActiveTimeline == null) return;

        double totalDuration = ViewModel.ActiveTimeline.TotalDuration;
        if (totalDuration <= 0) return;

        double canvasWidth = TrackCanvas.Width > 0 ? TrackCanvas.Width : TrackCanvas.ActualWidth;
        if (canvasWidth <= 0) return;

        double normalizedX = ViewModel.PlayheadTime / totalDuration;
        double x = Math.Clamp(normalizedX * canvasWidth, 0, canvasWidth);

        PlayheadLine.X1 = x;
        PlayheadLine.X2 = x;
        PlayheadLine.Y1 = 0;
        PlayheadLine.Y2 = TrackCanvas.ActualHeight > 0 ? TrackCanvas.ActualHeight : 160;

        Canvas.SetZIndex(PlayheadLine, 100);
    }

    /// <summary>
    /// Updates visual selection state of clip borders.
    /// </summary>
    private void UpdateClipSelection()
    {
        if (ViewModel == null) return;

        var accentBrush = FindResource("AccentBrush") as SolidColorBrush
            ?? new SolidColorBrush(Color.FromRgb(0x00, 0x78, 0xD4));
        var borderBrush = FindResource("BorderBrush") as SolidColorBrush
            ?? new SolidColorBrush(Color.FromRgb(0x3F, 0x3F, 0x46));

        foreach (var cv in _clipVisuals)
        {
            bool isSelected = (ViewModel.SelectedClip?.Id == cv.Clip.Id);
            cv.Container.BorderBrush = isSelected ? accentBrush : borderBrush;
            cv.Container.BorderThickness = new Thickness(isSelected ? 2 : 1);
        }

        // Redraw to show/hide trim handles
        RedrawAll();
    }

    private void OnClipClicked(TimelineClip clip, int index)
    {
        if (ViewModel == null) return;
        ViewModel.SelectedClip = clip;
        ViewModel.SelectedClipIndex = index;
    }

    private void OnTrackCanvasClick(object sender, MouseButtonEventArgs e)
    {
        if (ViewModel?.ActiveTimeline == null) return;

        double canvasWidth = TrackCanvas.Width > 0 ? TrackCanvas.Width : TrackCanvas.ActualWidth;
        if (canvasWidth <= 0) return;

        double totalDuration = ViewModel.ActiveTimeline.TotalDuration;
        Point clickPos = e.GetPosition(TrackCanvas);
        double normalizedX = Math.Clamp(clickPos.X / canvasWidth, 0, 1);
        double seekTime = normalizedX * totalDuration;

        ViewModel.Seek(seekTime);
    }

    // -- Trim handle drag --

    private void StartTrimDrag(TimelineClip clip, TrimEdge edge, MouseButtonEventArgs e)
    {
        _isTrimming = true;
        _trimEdge = edge;
        _trimClip = clip;
        _trimStartX = e.GetPosition(TrackCanvas).X;
        _trimOriginalValue = edge == TrimEdge.Left ? clip.InPoint : clip.OutPoint;

        TrackCanvas.MouseMove += OnTrimDragMove;
        TrackCanvas.MouseLeftButtonUp += OnTrimDragEnd;
        TrackCanvas.CaptureMouse();
    }

    private void OnTrimDragMove(object sender, MouseEventArgs e)
    {
        if (!_isTrimming || _trimClip == null) return;

        double currentX = e.GetPosition(TrackCanvas).X;
        double deltaX = currentX - _trimStartX;

        double canvasWidth = TrackCanvas.Width > 0 ? TrackCanvas.Width : TrackCanvas.ActualWidth;
        double totalDuration = ViewModel?.ActiveTimeline?.TotalDuration ?? 1.0;
        if (canvasWidth <= 0 || totalDuration <= 0) return;

        double deltaNormalized = deltaX / canvasWidth;
        double sourceRatio = _trimClip.SourceDuration > 0
            ? totalDuration / _trimClip.SourceDuration
            : 1.0;
        double deltaInSource = deltaNormalized * sourceRatio;

        if (_trimEdge == TrimEdge.Left)
        {
            _trimClip.InPoint = Math.Clamp(_trimOriginalValue + deltaInSource, 0, _trimClip.OutPoint - 0.01);
        }
        else
        {
            _trimClip.OutPoint = Math.Clamp(_trimOriginalValue + deltaInSource, _trimClip.InPoint + 0.01, 1.0);
        }

        RedrawAll();
    }

    private void OnTrimDragEnd(object sender, MouseButtonEventArgs e)
    {
        _isTrimming = false;
        _trimClip = null;
        _trimEdge = TrimEdge.None;

        TrackCanvas.MouseMove -= OnTrimDragMove;
        TrackCanvas.MouseLeftButtonUp -= OnTrimDragEnd;
        TrackCanvas.ReleaseMouseCapture();
    }

    // -- Context Menu --

    private ContextMenu CreateClipContextMenu(TimelineClip clip, int index)
    {
        var menu = new ContextMenu
        {
            Background = FindResource("SurfaceBrush") as Brush,
            Foreground = FindResource("TextPrimaryBrush") as Brush,
            BorderBrush = FindResource("BorderBrush") as Brush
        };

        var splitItem = new MenuItem
        {
            Header = "Split at Playhead",
            Icon = new TextBlock
            {
                FontFamily = new FontFamily("Segoe Fluent Icons"),
                Text = FindResource("IconSplit") as string,
                FontSize = 12
            }
        };
        splitItem.Click += (s, e) =>
        {
            if (ViewModel == null) return;
            ViewModel.SelectedClipIndex = index;
            ViewModel.SelectedClip = clip;
            ViewModel.SplitClipAtPlayhead();
        };
        menu.Items.Add(splitItem);

        var removeItem = new MenuItem
        {
            Header = "Remove Clip",
            Icon = new TextBlock
            {
                FontFamily = new FontFamily("Segoe Fluent Icons"),
                Text = FindResource("IconDelete") as string,
                FontSize = 12
            }
        };
        removeItem.Click += (s, e) =>
        {
            if (ViewModel == null) return;
            ViewModel.SelectedClipIndex = index;
            ViewModel.SelectedClip = clip;
            ViewModel.RemoveSelectedClip();
        };
        menu.Items.Add(removeItem);

        menu.Items.Add(new Separator { Background = FindResource("BorderBrush") as Brush });

        var inPointItem = new MenuItem
        {
            Header = "Set In Point",
            Icon = new TextBlock
            {
                FontFamily = new FontFamily("Segoe Fluent Icons"),
                Text = FindResource("IconSkipBackward") as string,
                FontSize = 12
            }
        };
        inPointItem.Click += (s, e) =>
        {
            if (ViewModel == null) return;
            ViewModel.SelectedClip = clip;
            ViewModel.SetInPoint();
        };
        menu.Items.Add(inPointItem);

        var outPointItem = new MenuItem
        {
            Header = "Set Out Point",
            Icon = new TextBlock
            {
                FontFamily = new FontFamily("Segoe Fluent Icons"),
                Text = FindResource("IconSkipForward") as string,
                FontSize = 12
            }
        };
        outPointItem.Click += (s, e) =>
        {
            if (ViewModel == null) return;
            ViewModel.SelectedClip = clip;
            ViewModel.SetOutPoint();
        };
        menu.Items.Add(outPointItem);

        return menu;
    }

    // -- Helpers --

    private static string FormatDuration(double seconds)
    {
        if (seconds < 0) seconds = 0;
        var ts = TimeSpan.FromSeconds(seconds);
        return ts.TotalHours >= 1
            ? ts.ToString(@"h\:mm\:ss\.f")
            : ts.ToString(@"m\:ss\.f");
    }
}
