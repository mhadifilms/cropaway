using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using CropawayWindows.Models;
using CropawayWindows.ViewModels;

namespace CropawayWindows.Controls;

/// <summary>
/// Renders a preview of the cropped video output. Uses a VisualBrush sourced from
/// the MediaElement to display only the cropped region, scaled to fill the available space.
/// Supports all four crop modes: Rectangle, Circle, Freehand, and AI.
/// Updates in real-time as the video plays and crop parameters change (including keyframes).
/// </summary>
public class CropPreviewControl : FrameworkElement
{
    // Dependency property for the video source visual (the MediaElement)
    public static readonly DependencyProperty VideoSourceProperty =
        DependencyProperty.Register(nameof(VideoSource), typeof(Visual), typeof(CropPreviewControl),
            new PropertyMetadata(null, OnVisualPropertyChanged));

    // Dependency property for the video width (natural resolution)
    public static readonly DependencyProperty VideoWidthProperty =
        DependencyProperty.Register(nameof(VideoWidth), typeof(double), typeof(CropPreviewControl),
            new PropertyMetadata(0.0, OnVisualPropertyChanged));

    // Dependency property for the video height (natural resolution)
    public static readonly DependencyProperty VideoHeightProperty =
        DependencyProperty.Register(nameof(VideoHeight), typeof(double), typeof(CropPreviewControl),
            new PropertyMetadata(0.0, OnVisualPropertyChanged));

    public Visual? VideoSource
    {
        get => (Visual?)GetValue(VideoSourceProperty);
        set => SetValue(VideoSourceProperty, value);
    }

    public double VideoWidth
    {
        get => (double)GetValue(VideoWidthProperty);
        set => SetValue(VideoWidthProperty, value);
    }

    public double VideoHeight
    {
        get => (double)GetValue(VideoHeightProperty);
        set => SetValue(VideoHeightProperty, value);
    }

    private CropEditorViewModel? _viewModel;

    private static readonly Brush CheckerBrush = CreateCheckerboardBrush();

    public CropPreviewControl()
    {
        ClipToBounds = true;
        DataContextChanged += OnDataContextChanged;
        SizeChanged += (_, _) => InvalidateVisual();
    }

    private void OnDataContextChanged(object sender, DependencyPropertyChangedEventArgs e)
    {
        if (_viewModel != null)
        {
            _viewModel.PropertyChanged -= OnViewModelPropertyChanged;
        }

        if (DataContext is CropEditorViewModel vm)
        {
            _viewModel = vm;
            vm.PropertyChanged += OnViewModelPropertyChanged;
        }
        else
        {
            _viewModel = null;
        }

        InvalidateVisual();
    }

    private void OnViewModelPropertyChanged(object? sender, System.ComponentModel.PropertyChangedEventArgs e)
    {
        // Re-render when any crop property changes
        if (e.PropertyName is nameof(CropEditorViewModel.CropRect) or
            nameof(CropEditorViewModel.CircleCenter) or
            nameof(CropEditorViewModel.CircleRadius) or
            nameof(CropEditorViewModel.FreehandPoints) or
            nameof(CropEditorViewModel.AiBoundingBox) or
            nameof(CropEditorViewModel.Mode) or
            nameof(CropEditorViewModel.IsPreviewMode))
        {
            InvalidateVisual();
        }
    }

    private static void OnVisualPropertyChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        ((CropPreviewControl)d).InvalidateVisual();
    }

    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);

        if (_viewModel == null || !_viewModel.IsPreviewMode || VideoSource == null)
            return;

        if (ActualWidth <= 0 || ActualHeight <= 0)
            return;

        var controlRect = new Rect(0, 0, ActualWidth, ActualHeight);

        // Draw checkerboard background (visible for circle/freehand shapes to show transparency)
        dc.DrawRectangle(CheckerBrush, null, controlRect);

        // Get the normalized crop region for the current mode
        var cropRect = _viewModel.EffectiveCropRect;
        if (cropRect.Width <= 0 || cropRect.Height <= 0)
        {
            cropRect = new Rect(0, 0, 1, 1);
        }

        // The MediaElement renders with Stretch="Uniform", so we need to figure out
        // the actual video area within the source visual. We use the VisualBrush
        // Viewbox to select the crop region from the source, mapped through the
        // letterboxed video area.

        // First, compute the letterbox offset within the source visual.
        // The source is the MediaElement which has Stretch="Uniform".
        var sourceElement = VideoSource as FrameworkElement;
        double sourceWidth = sourceElement?.ActualWidth ?? ActualWidth;
        double sourceHeight = sourceElement?.ActualHeight ?? ActualHeight;

        if (sourceWidth <= 0 || sourceHeight <= 0 || VideoWidth <= 0 || VideoHeight <= 0)
            return;

        // Calculate the video display rect within the source (letterboxed)
        var videoAspect = VideoWidth / VideoHeight;
        var sourceAspect = sourceWidth / sourceHeight;
        double displayWidth, displayHeight, offsetX, offsetY;

        if (videoAspect > sourceAspect)
        {
            // Video wider than source - letterboxed top/bottom
            displayWidth = sourceWidth;
            displayHeight = sourceWidth / videoAspect;
            offsetX = 0;
            offsetY = (sourceHeight - displayHeight) / 2;
        }
        else
        {
            // Video taller than source - pillarboxed left/right
            displayHeight = sourceHeight;
            displayWidth = sourceHeight * videoAspect;
            offsetX = (sourceWidth - displayWidth) / 2;
            offsetY = 0;
        }

        // Convert normalized crop rect to source-relative coordinates (0-1 of source)
        double viewboxX = (offsetX + cropRect.X * displayWidth) / sourceWidth;
        double viewboxY = (offsetY + cropRect.Y * displayHeight) / sourceHeight;
        double viewboxW = (cropRect.Width * displayWidth) / sourceWidth;
        double viewboxH = (cropRect.Height * displayHeight) / sourceHeight;

        // Clamp to valid range
        viewboxX = Math.Clamp(viewboxX, 0, 1);
        viewboxY = Math.Clamp(viewboxY, 0, 1);
        viewboxW = Math.Clamp(viewboxW, 0.001, 1 - viewboxX);
        viewboxH = Math.Clamp(viewboxH, 0.001, 1 - viewboxY);

        var viewbox = new Rect(viewboxX, viewboxY, viewboxW, viewboxH);

        // Create a VisualBrush from the MediaElement, using the crop region as viewbox
        var videoBrush = new VisualBrush(VideoSource)
        {
            Viewbox = viewbox,
            ViewboxUnits = BrushMappingMode.RelativeToBoundingBox,
            Stretch = Stretch.Uniform,
            AlignmentX = AlignmentX.Center,
            AlignmentY = AlignmentY.Center
        };

        // Calculate the aspect ratio of the crop region
        double cropAspectRatio = (cropRect.Width * VideoWidth) / (cropRect.Height * VideoHeight);
        double controlAspect = ActualWidth / ActualHeight;

        // Calculate the display rect that fits the cropped content uniformly
        double renderWidth, renderHeight, renderX, renderY;
        if (cropAspectRatio > controlAspect)
        {
            // Crop is wider than control
            renderWidth = ActualWidth;
            renderHeight = ActualWidth / cropAspectRatio;
            renderX = 0;
            renderY = (ActualHeight - renderHeight) / 2;
        }
        else
        {
            // Crop is taller than control
            renderHeight = ActualHeight;
            renderWidth = ActualHeight * cropAspectRatio;
            renderX = (ActualWidth - renderWidth) / 2;
            renderY = 0;
        }

        var renderRect = new Rect(renderX, renderY, renderWidth, renderHeight);

        // Apply mode-specific clipping geometry
        switch (_viewModel.Mode)
        {
            case CropMode.Circle:
                DrawCirclePreview(dc, videoBrush, renderRect, cropRect);
                break;

            case CropMode.Freehand:
                DrawFreehandPreview(dc, videoBrush, renderRect, cropRect);
                break;

            case CropMode.Rectangle:
            case CropMode.AI:
            default:
                // Simple rectangle fill
                dc.DrawRectangle(videoBrush, null, renderRect);
                break;
        }
    }

    private void DrawCirclePreview(DrawingContext dc, VisualBrush videoBrush, Rect renderRect, Rect cropRect)
    {
        if (_viewModel == null) return;

        // The circle in the preview should be centered and fit within the render rect
        // The circle's center is at the center of the bounding box (cropRect)
        // The radius relative to the bounding box determines the ellipse

        // In the crop region, the circle fills the bounding box.
        // Compute the circle as centered in the renderRect
        double centerX = renderRect.X + renderRect.Width / 2;
        double centerY = renderRect.Y + renderRect.Height / 2;

        // The radius in render coords: since the cropRect is the circle's bounding box,
        // the circle fills it. The radius is half the min dimension.
        double radiusPixelX = renderRect.Width / 2;
        double radiusPixelY = renderRect.Height / 2;

        // Use the actual circle radius to determine if we need an equal-radius circle
        // or if we should use the bounding box. Since EffectiveCropRect for circle
        // is the bounding square, we can use a true circle.
        double radiusPixel = Math.Min(radiusPixelX, radiusPixelY);

        // Push clip for circle
        var clipGeometry = new EllipseGeometry(new Point(centerX, centerY), radiusPixel, radiusPixel);
        dc.PushClip(clipGeometry);
        dc.DrawRectangle(videoBrush, null, renderRect);
        dc.Pop();
    }

    private void DrawFreehandPreview(DrawingContext dc, VisualBrush videoBrush, Rect renderRect, Rect cropRect)
    {
        if (_viewModel == null) return;

        var points = _viewModel.FreehandPoints;
        if (points.Count < 3)
        {
            // Fall back to rectangle if not enough points
            dc.DrawRectangle(videoBrush, null, renderRect);
            return;
        }

        // Convert normalized freehand points to render coordinates.
        // The freehand points are in full-frame normalized coords (0-1).
        // The cropRect is the bounding box of those points.
        // We need to map each point from full-frame to renderRect space.
        var geometry = new StreamGeometry();
        using (var ctx = geometry.Open())
        {
            var firstPt = NormalizedToRenderPoint(points[0], cropRect, renderRect);
            ctx.BeginFigure(firstPt, true, true);

            for (int i = 1; i < points.Count; i++)
            {
                ctx.LineTo(NormalizedToRenderPoint(points[i], cropRect, renderRect), true, true);
            }
        }
        geometry.Freeze();

        dc.PushClip(geometry);
        dc.DrawRectangle(videoBrush, null, renderRect);
        dc.Pop();
    }

    /// <summary>
    /// Maps a normalized (0-1) point within the full video frame to a pixel
    /// coordinate within the renderRect, accounting for the cropRect offset.
    /// </summary>
    private static Point NormalizedToRenderPoint(Point normalized, Rect cropRect, Rect renderRect)
    {
        // Map from full-frame normalized to crop-relative normalized
        double relX = (normalized.X - cropRect.X) / cropRect.Width;
        double relY = (normalized.Y - cropRect.Y) / cropRect.Height;

        // Map to render pixel coordinates
        return new Point(
            renderRect.X + relX * renderRect.Width,
            renderRect.Y + relY * renderRect.Height);
    }

    /// <summary>
    /// Creates a simple checkerboard brush to indicate transparency areas
    /// (useful for circle and freehand modes).
    /// </summary>
    private static Brush CreateCheckerboardBrush()
    {
        var size = 8.0;
        var darkGray = Color.FromRgb(40, 40, 40);
        var lightGray = Color.FromRgb(50, 50, 50);

        var drawingGroup = new DrawingGroup();
        drawingGroup.Children.Add(new GeometryDrawing(
            new SolidColorBrush(darkGray), null,
            new RectangleGeometry(new Rect(0, 0, size * 2, size * 2))));
        drawingGroup.Children.Add(new GeometryDrawing(
            new SolidColorBrush(lightGray), null,
            new RectangleGeometry(new Rect(0, 0, size, size))));
        drawingGroup.Children.Add(new GeometryDrawing(
            new SolidColorBrush(lightGray), null,
            new RectangleGeometry(new Rect(size, size, size, size))));

        var brush = new DrawingBrush(drawingGroup)
        {
            TileMode = TileMode.Tile,
            ViewportUnits = BrushMappingMode.Absolute,
            Viewport = new Rect(0, 0, size * 2, size * 2)
        };
        brush.Freeze();
        return brush;
    }
}
