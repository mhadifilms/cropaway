using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Shapes;
using CropawayWindows.Models;
using CropawayWindows.ViewModels;

namespace CropawayWindows.Controls;

/// <summary>
/// Custom control that draws crop overlays on top of the video preview.
/// Supports rectangle, circle, freehand mask, and AI bounding box crop modes.
/// All coordinates are normalized 0-1 and converted to pixel positions based on actual video area.
/// </summary>
public class CropOverlayControl : Canvas
{
    // Dependency properties for video dimensions
    public static readonly DependencyProperty VideoWidthProperty =
        DependencyProperty.Register(nameof(VideoWidth), typeof(double), typeof(CropOverlayControl),
            new PropertyMetadata(0.0, OnVideoSizeChanged));

    public static readonly DependencyProperty VideoHeightProperty =
        DependencyProperty.Register(nameof(VideoHeight), typeof(double), typeof(CropOverlayControl),
            new PropertyMetadata(0.0, OnVideoSizeChanged));

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
    private bool _isDragging;
    private DragHandle _activeDragHandle = DragHandle.None;
    private Point _dragStartNormalized;
    private Rect _dragStartRect;
    private Point _dragStartCircleCenter;
    private double _dragStartCircleRadius;

    private static readonly Brush OverlayBrush = new SolidColorBrush(Color.FromArgb(128, 0, 0, 0));
    private static readonly Brush CropBorderBrush = new SolidColorBrush(Color.FromRgb(0, 180, 255));
    private static readonly Brush HandleBrush = new SolidColorBrush(Color.FromRgb(0, 180, 255));
    private static readonly Brush HandleFillBrush = Brushes.White;
    private static readonly Brush GuidelineBrush = new SolidColorBrush(Color.FromArgb(80, 255, 255, 255));
    private static readonly Brush FreehandBrush = new SolidColorBrush(Color.FromRgb(0, 255, 128));
    private static readonly Brush AIBrush = new SolidColorBrush(Color.FromRgb(255, 185, 0));
    private static readonly Brush LabelBackgroundBrush = new SolidColorBrush(Color.FromArgb(180, 0, 0, 0));
    private const double HandleSize = 8;
    private const double HitTestMargin = 12;
    private const double LabelFontSize = 11;
    private const double LabelPadding = 4;

    public CropOverlayControl()
    {
        ClipToBounds = true;
        Background = Brushes.Transparent; // Needed for hit testing
        IsHitTestVisible = true;

        Loaded += OnLoaded;
        DataContextChanged += OnDataContextChanged;
        SizeChanged += (s, e) => InvalidateVisual();
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        BindViewModel();
    }

    private void OnDataContextChanged(object sender, DependencyPropertyChangedEventArgs e)
    {
        BindViewModel();
    }

    private void BindViewModel()
    {
        if (DataContext is CropEditorViewModel vm)
        {
            _viewModel = vm;
            vm.PropertyChanged += (s, e) => InvalidateVisual();
        }
    }

    private static void OnVideoSizeChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        ((CropOverlayControl)d).InvalidateVisual();
    }

    // Calculate the actual video display area within this control (letterboxed)
    private Rect GetVideoDisplayRect()
    {
        if (VideoWidth <= 0 || VideoHeight <= 0 || ActualWidth <= 0 || ActualHeight <= 0)
            return new Rect(0, 0, ActualWidth, ActualHeight);

        var videoAspect = VideoWidth / VideoHeight;
        var controlAspect = ActualWidth / ActualHeight;

        double displayWidth, displayHeight, offsetX, offsetY;

        if (videoAspect > controlAspect)
        {
            // Video is wider - pillarbox
            displayWidth = ActualWidth;
            displayHeight = ActualWidth / videoAspect;
            offsetX = 0;
            offsetY = (ActualHeight - displayHeight) / 2;
        }
        else
        {
            // Video is taller - letterbox
            displayHeight = ActualHeight;
            displayWidth = ActualHeight * videoAspect;
            offsetX = (ActualWidth - displayWidth) / 2;
            offsetY = 0;
        }

        return new Rect(offsetX, offsetY, displayWidth, displayHeight);
    }

    // Convert normalized (0-1) coordinates to pixel coordinates within display area
    private Point NormalizedToPixel(Point normalized)
    {
        var displayRect = GetVideoDisplayRect();
        return new Point(
            displayRect.X + normalized.X * displayRect.Width,
            displayRect.Y + normalized.Y * displayRect.Height);
    }

    private Point PixelToNormalized(Point pixel)
    {
        var displayRect = GetVideoDisplayRect();
        return new Point(
            Math.Clamp((pixel.X - displayRect.X) / displayRect.Width, 0, 1),
            Math.Clamp((pixel.Y - displayRect.Y) / displayRect.Height, 0, 1));
    }

    private Rect NormalizedRectToPixel(Rect normalized)
    {
        var topLeft = NormalizedToPixel(new Point(normalized.X, normalized.Y));
        var bottomRight = NormalizedToPixel(new Point(normalized.Right, normalized.Bottom));
        return new Rect(topLeft, bottomRight);
    }

    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);

        if (_viewModel == null) return;

        var displayRect = GetVideoDisplayRect();
        if (displayRect.Width <= 0 || displayRect.Height <= 0) return;

        var pen = new Pen(CropBorderBrush, 2);
        pen.Freeze();

        switch (_viewModel.Mode)
        {
            case CropMode.Rectangle:
                DrawRectangleCrop(dc, displayRect, pen);
                break;
            case CropMode.Circle:
                DrawCircleCrop(dc, displayRect, pen);
                break;
            case CropMode.Freehand:
                DrawFreehandCrop(dc, displayRect);
                break;
            case CropMode.AI:
                DrawAICrop(dc, displayRect);
                break;
        }
    }

    private void DrawRectangleCrop(DrawingContext dc, Rect displayRect, Pen pen)
    {
        var cropRect = NormalizedRectToPixel(_viewModel!.CropRect);

        // Draw darkened overlay outside crop area
        var overlayGeometry = new CombinedGeometry(
            GeometryCombineMode.Exclude,
            new RectangleGeometry(displayRect),
            new RectangleGeometry(cropRect));
        dc.DrawGeometry(OverlayBrush, null, overlayGeometry);

        // Draw crop border
        dc.DrawRectangle(null, pen, cropRect);

        // Draw rule-of-thirds guidelines
        var guidePen = new Pen(GuidelineBrush, 0.5);
        guidePen.Freeze();
        for (int i = 1; i <= 2; i++)
        {
            var x = cropRect.X + cropRect.Width * i / 3.0;
            var y = cropRect.Y + cropRect.Height * i / 3.0;
            dc.DrawLine(guidePen, new Point(x, cropRect.Y), new Point(x, cropRect.Bottom));
            dc.DrawLine(guidePen, new Point(cropRect.X, y), new Point(cropRect.Right, y));
        }

        // Draw resize handles
        DrawHandle(dc, cropRect.TopLeft);          // Top-left
        DrawHandle(dc, cropRect.TopRight);         // Top-right
        DrawHandle(dc, cropRect.BottomLeft);       // Bottom-left
        DrawHandle(dc, cropRect.BottomRight);      // Bottom-right
        DrawHandle(dc, new Point(cropRect.X + cropRect.Width / 2, cropRect.Y));          // Top-center
        DrawHandle(dc, new Point(cropRect.X + cropRect.Width / 2, cropRect.Bottom));     // Bottom-center
        DrawHandle(dc, new Point(cropRect.X, cropRect.Y + cropRect.Height / 2));         // Left-center
        DrawHandle(dc, new Point(cropRect.Right, cropRect.Y + cropRect.Height / 2));     // Right-center

        // Draw dimension labels
        DrawDimensionLabels(dc, displayRect);
    }

    private void DrawCircleCrop(DrawingContext dc, Rect displayRect, Pen pen)
    {
        var center = NormalizedToPixel(_viewModel!.CircleCenter);
        var radiusX = _viewModel.CircleRadius * displayRect.Width;
        var radiusY = _viewModel.CircleRadius * displayRect.Height;
        var radius = Math.Min(radiusX, radiusY);

        // Darkened overlay outside circle
        var overlayGeometry = new CombinedGeometry(
            GeometryCombineMode.Exclude,
            new RectangleGeometry(displayRect),
            new EllipseGeometry(center, radius, radius));
        dc.DrawGeometry(OverlayBrush, null, overlayGeometry);

        // Draw circle border
        dc.DrawEllipse(null, pen, center, radius, radius);

        // Draw center crosshair
        var crossPen = new Pen(GuidelineBrush, 1);
        crossPen.Freeze();
        dc.DrawLine(crossPen, new Point(center.X - 10, center.Y), new Point(center.X + 10, center.Y));
        dc.DrawLine(crossPen, new Point(center.X, center.Y - 10), new Point(center.X, center.Y + 10));

        // Draw radius handle
        DrawHandle(dc, new Point(center.X + radius, center.Y));
        DrawHandle(dc, center);

        // Draw dimension labels
        DrawDimensionLabels(dc, displayRect);
    }

    private void DrawFreehandCrop(DrawingContext dc, Rect displayRect)
    {
        var points = _viewModel!.FreehandPoints;
        if (points.Count < 2) return;

        var freehandPen = new Pen(FreehandBrush, 2);
        freehandPen.Freeze();

        // Draw filled polygon with overlay
        var geometry = new StreamGeometry();
        using (var ctx = geometry.Open())
        {
            var firstPixel = NormalizedToPixel(points[0]);
            ctx.BeginFigure(firstPixel, true, true);

            for (int i = 1; i < points.Count; i++)
            {
                ctx.LineTo(NormalizedToPixel(points[i]), true, true);
            }
        }
        geometry.Freeze();

        // Draw darkened overlay outside freehand path
        var overlayGeometry = new CombinedGeometry(
            GeometryCombineMode.Exclude,
            new RectangleGeometry(displayRect),
            geometry);
        dc.DrawGeometry(OverlayBrush, null, overlayGeometry);

        // Draw freehand path outline
        dc.DrawGeometry(null, freehandPen, geometry);

        // Draw vertices
        foreach (var point in points)
        {
            DrawHandle(dc, NormalizedToPixel(point));
        }
    }

    private void DrawAICrop(DrawingContext dc, Rect displayRect)
    {
        var bbox = _viewModel!.AiBoundingBox;
        if (bbox.Width <= 0 || bbox.Height <= 0) return;

        var pixelRect = NormalizedRectToPixel(bbox);
        var aiPen = new Pen(AIBrush, 2) { DashStyle = DashStyles.Dash };
        aiPen.Freeze();

        // Darkened overlay outside AI bounding box
        var overlayGeometry = new CombinedGeometry(
            GeometryCombineMode.Exclude,
            new RectangleGeometry(displayRect),
            new RectangleGeometry(pixelRect));
        dc.DrawGeometry(OverlayBrush, null, overlayGeometry);

        // Draw AI bounding box
        dc.DrawRectangle(null, aiPen, pixelRect);

        // Draw corner handles
        DrawHandle(dc, pixelRect.TopLeft, AIBrush);
        DrawHandle(dc, pixelRect.TopRight, AIBrush);
        DrawHandle(dc, pixelRect.BottomLeft, AIBrush);
        DrawHandle(dc, pixelRect.BottomRight, AIBrush);

        // Draw "AI" label
        var label = new FormattedText("AI Tracked",
            System.Globalization.CultureInfo.CurrentCulture,
            System.Windows.FlowDirection.LeftToRight,
            new Typeface("Segoe UI"),
            11, AIBrush,
            VisualTreeHelper.GetDpi(this).PixelsPerDip);
        dc.DrawText(label, new Point(pixelRect.X + 4, pixelRect.Y - 16));

        // Draw dimension labels
        DrawDimensionLabels(dc, displayRect);
    }

    private void DrawHandle(DrawingContext dc, Point center, Brush? brush = null)
    {
        var fill = brush ?? HandleBrush;
        dc.DrawRectangle(HandleFillBrush, new Pen(fill, 2),
            new Rect(center.X - HandleSize / 2, center.Y - HandleSize / 2, HandleSize, HandleSize));
    }

    /// <summary>
    /// Draws dimension labels showing pixel dimensions near the crop area.
    /// Only renders when VideoWidth and VideoHeight are available.
    /// </summary>
    private void DrawDimensionLabels(DrawingContext dc, Rect displayRect)
    {
        if (VideoWidth <= 0 || VideoHeight <= 0 || _viewModel == null) return;

        var dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip;

        switch (_viewModel.Mode)
        {
            case CropMode.Rectangle:
                DrawRectangleDimensionLabels(dc, displayRect, dpi);
                break;
            case CropMode.Circle:
                DrawCircleDimensionLabels(dc, displayRect, dpi);
                break;
            case CropMode.AI:
                DrawAIDimensionLabels(dc, displayRect, dpi);
                break;
        }
    }

    private void DrawRectangleDimensionLabels(DrawingContext dc, Rect displayRect, double dpi)
    {
        var cropRect = _viewModel!.CropRect;
        var pixelRect = NormalizedRectToPixel(cropRect);

        // Calculate pixel dimensions from normalized coordinates
        var widthPx = (int)Math.Round(cropRect.Width * VideoWidth);
        var heightPx = (int)Math.Round(cropRect.Height * VideoHeight);
        var xPx = (int)Math.Round(cropRect.X * VideoWidth);
        var yPx = (int)Math.Round(cropRect.Y * VideoHeight);

        // Dimension label: "1280 x 720" below bottom edge, centered
        var dimensionText = $"{widthPx} x {heightPx}";
        var dimensionFormatted = CreateFormattedText(dimensionText, Brushes.White, dpi);

        var dimX = pixelRect.X + (pixelRect.Width - dimensionFormatted.Width) / 2;
        var dimY = pixelRect.Bottom + HandleSize + 4;
        DrawLabelWithBackground(dc, dimensionFormatted, new Point(dimX, dimY));

        // Position label: "X: 100, Y: 50" above top edge, centered
        var positionText = $"X: {xPx}, Y: {yPx}";
        var positionFormatted = CreateFormattedText(positionText, Brushes.White, dpi);

        var posX = pixelRect.X + (pixelRect.Width - positionFormatted.Width) / 2;
        var posY = pixelRect.Y - HandleSize - 4 - positionFormatted.Height;
        DrawLabelWithBackground(dc, positionFormatted, new Point(posX, posY));
    }

    private void DrawCircleDimensionLabels(DrawingContext dc, Rect displayRect, double dpi)
    {
        var center = NormalizedToPixel(_viewModel!.CircleCenter);
        var radiusX = _viewModel.CircleRadius * displayRect.Width;
        var radiusY = _viewModel.CircleRadius * displayRect.Height;
        var radius = Math.Min(radiusX, radiusY);

        // Calculate pixel values
        var radiusPx = (int)Math.Round(_viewModel.CircleRadius * Math.Min(VideoWidth, VideoHeight));
        var centerXPx = (int)Math.Round(_viewModel.CircleCenter.X * VideoWidth);
        var centerYPx = (int)Math.Round(_viewModel.CircleCenter.Y * VideoHeight);

        // Radius label: "R: 384px" below the circle
        var radiusText = $"R: {radiusPx}px";
        var radiusFormatted = CreateFormattedText(radiusText, Brushes.White, dpi);

        var rLabelX = center.X - radiusFormatted.Width / 2;
        var rLabelY = center.Y + radius + HandleSize + 4;
        DrawLabelWithBackground(dc, radiusFormatted, new Point(rLabelX, rLabelY));

        // Center position label: "Center: 640, 360" above the circle
        var centerText = $"Center: {centerXPx}, {centerYPx}";
        var centerFormatted = CreateFormattedText(centerText, Brushes.White, dpi);

        var cLabelX = center.X - centerFormatted.Width / 2;
        var cLabelY = center.Y - radius - HandleSize - 4 - centerFormatted.Height;
        DrawLabelWithBackground(dc, centerFormatted, new Point(cLabelX, cLabelY));
    }

    private void DrawAIDimensionLabels(DrawingContext dc, Rect displayRect, double dpi)
    {
        var bbox = _viewModel!.AiBoundingBox;
        if (bbox.Width <= 0 || bbox.Height <= 0) return;

        var pixelRect = NormalizedRectToPixel(bbox);

        // Calculate pixel dimensions
        var widthPx = (int)Math.Round(bbox.Width * VideoWidth);
        var heightPx = (int)Math.Round(bbox.Height * VideoHeight);

        // Dimension label: "1024 x 768" below bottom edge, centered
        var dimensionText = $"{widthPx} x {heightPx}";
        var dimensionFormatted = CreateFormattedText(dimensionText, Brushes.White, dpi);

        var dimX = pixelRect.X + (pixelRect.Width - dimensionFormatted.Width) / 2;
        var dimY = pixelRect.Bottom + HandleSize + 4;
        DrawLabelWithBackground(dc, dimensionFormatted, new Point(dimX, dimY));
    }

    private FormattedText CreateFormattedText(string text, Brush foreground, double pixelsPerDip)
    {
        return new FormattedText(
            text,
            System.Globalization.CultureInfo.CurrentCulture,
            System.Windows.FlowDirection.LeftToRight,
            new Typeface("Segoe UI"),
            LabelFontSize,
            foreground,
            pixelsPerDip);
    }

    private void DrawLabelWithBackground(DrawingContext dc, FormattedText text, Point position)
    {
        var backgroundRect = new Rect(
            position.X - LabelPadding,
            position.Y - LabelPadding,
            text.Width + LabelPadding * 2,
            text.Height + LabelPadding * 2);

        dc.DrawRoundedRectangle(LabelBackgroundBrush, null, backgroundRect, 3, 3);
        dc.DrawText(text, position);
    }

    // MARK: - Mouse interaction

    protected override void OnMouseLeftButtonDown(MouseButtonEventArgs e)
    {
        if (_viewModel == null) return;

        var pos = e.GetPosition(this);
        var normalized = PixelToNormalized(pos);

        _dragStartNormalized = normalized;
        _dragStartRect = _viewModel.CropRect;
        _dragStartCircleCenter = _viewModel.CircleCenter;
        _dragStartCircleRadius = _viewModel.CircleRadius;

        // Determine what was hit
        _activeDragHandle = HitTest(pos);

        if (_viewModel.Mode == CropMode.Freehand && _viewModel.IsDrawing)
        {
            _viewModel.ContinueDrawing(normalized);
            return;
        }

        if (_viewModel.Mode == CropMode.Freehand && _activeDragHandle == DragHandle.None)
        {
            _viewModel.StartDrawing(normalized);
            return;
        }

        if (_activeDragHandle != DragHandle.None)
        {
            _isDragging = true;
            CaptureMouse();
        }

        e.Handled = true;
    }

    protected override void OnMouseMove(MouseEventArgs e)
    {
        if (_viewModel == null) return;

        var pos = e.GetPosition(this);
        var normalized = PixelToNormalized(pos);

        if (_viewModel.Mode == CropMode.Freehand && _viewModel.IsDrawing)
        {
            _viewModel.ContinueDrawing(normalized);
            InvalidateVisual();
            return;
        }

        if (!_isDragging)
        {
            // Update cursor based on hover position
            var hoverHandle = HitTest(pos);
            Cursor = hoverHandle switch
            {
                DragHandle.TopLeft => Cursors.SizeNWSE,
                DragHandle.BottomRight => Cursors.SizeNWSE,
                DragHandle.TopRight => Cursors.SizeNESW,
                DragHandle.BottomLeft => Cursors.SizeNESW,
                DragHandle.Top => Cursors.SizeNS,
                DragHandle.Bottom => Cursors.SizeNS,
                DragHandle.Left => Cursors.SizeWE,
                DragHandle.Right => Cursors.SizeWE,
                DragHandle.RadiusHandle => Cursors.SizeWE,
                DragHandle.Body => Cursors.SizeAll,
                _ => _viewModel.Mode == CropMode.Freehand ? Cursors.Cross : Cursors.Arrow
            };
            return;
        }

        var deltaX = normalized.X - _dragStartNormalized.X;
        var deltaY = normalized.Y - _dragStartNormalized.Y;

        switch (_viewModel.Mode)
        {
            case CropMode.Rectangle:
                HandleRectangleDrag(deltaX, deltaY);
                break;
            case CropMode.Circle:
                HandleCircleDrag(normalized, deltaX, deltaY);
                break;
            case CropMode.AI:
                HandleAIDrag(deltaX, deltaY);
                break;
        }

        InvalidateVisual();
        e.Handled = true;
    }

    protected override void OnMouseLeftButtonUp(MouseButtonEventArgs e)
    {
        if (_viewModel?.Mode == CropMode.Freehand && _viewModel.IsDrawing)
        {
            _viewModel.EndDrawing();
            InvalidateVisual();
        }

        if (_isDragging)
        {
            _isDragging = false;
            ReleaseMouseCapture();
            _viewModel?.NotifyCropEditEnded();
        }

        _activeDragHandle = DragHandle.None;
        e.Handled = true;
    }

    private void HandleRectangleDrag(double deltaX, double deltaY)
    {
        var rect = _dragStartRect;

        switch (_activeDragHandle)
        {
            case DragHandle.Body:
                var newX = Math.Clamp(rect.X + deltaX, 0, 1 - rect.Width);
                var newY = Math.Clamp(rect.Y + deltaY, 0, 1 - rect.Height);
                _viewModel!.CropRect = new Rect(newX, newY, rect.Width, rect.Height);
                break;

            case DragHandle.TopLeft:
                var tlX = Math.Clamp(rect.X + deltaX, 0, rect.Right - 0.01);
                var tlY = Math.Clamp(rect.Y + deltaY, 0, rect.Bottom - 0.01);
                _viewModel!.CropRect = new Rect(tlX, tlY, rect.Right - tlX, rect.Bottom - tlY);
                break;

            case DragHandle.TopRight:
                var trW = Math.Clamp(rect.Width + deltaX, 0.01, 1 - rect.X);
                var trY = Math.Clamp(rect.Y + deltaY, 0, rect.Bottom - 0.01);
                _viewModel!.CropRect = new Rect(rect.X, trY, trW, rect.Bottom - trY);
                break;

            case DragHandle.BottomLeft:
                var blX = Math.Clamp(rect.X + deltaX, 0, rect.Right - 0.01);
                var blH = Math.Clamp(rect.Height + deltaY, 0.01, 1 - rect.Y);
                _viewModel!.CropRect = new Rect(blX, rect.Y, rect.Right - blX, blH);
                break;

            case DragHandle.BottomRight:
                var brW = Math.Clamp(rect.Width + deltaX, 0.01, 1 - rect.X);
                var brH = Math.Clamp(rect.Height + deltaY, 0.01, 1 - rect.Y);
                _viewModel!.CropRect = new Rect(rect.X, rect.Y, brW, brH);
                break;

            case DragHandle.Top:
                var tY = Math.Clamp(rect.Y + deltaY, 0, rect.Bottom - 0.01);
                _viewModel!.CropRect = new Rect(rect.X, tY, rect.Width, rect.Bottom - tY);
                break;

            case DragHandle.Bottom:
                var bH = Math.Clamp(rect.Height + deltaY, 0.01, 1 - rect.Y);
                _viewModel!.CropRect = new Rect(rect.X, rect.Y, rect.Width, bH);
                break;

            case DragHandle.Left:
                var lX = Math.Clamp(rect.X + deltaX, 0, rect.Right - 0.01);
                _viewModel!.CropRect = new Rect(lX, rect.Y, rect.Right - lX, rect.Height);
                break;

            case DragHandle.Right:
                var rW = Math.Clamp(rect.Width + deltaX, 0.01, 1 - rect.X);
                _viewModel!.CropRect = new Rect(rect.X, rect.Y, rW, rect.Height);
                break;
        }
    }

    private void HandleCircleDrag(Point normalized, double deltaX, double deltaY)
    {
        switch (_activeDragHandle)
        {
            case DragHandle.Body:
                _viewModel!.CircleCenter = new Point(
                    Math.Clamp(_dragStartCircleCenter.X + deltaX, 0, 1),
                    Math.Clamp(_dragStartCircleCenter.Y + deltaY, 0, 1));
                break;

            case DragHandle.RadiusHandle:
                var center = _viewModel!.CircleCenter;
                var dx = normalized.X - center.X;
                var dy = normalized.Y - center.Y;
                _viewModel.CircleRadius = Math.Clamp(Math.Sqrt(dx * dx + dy * dy), 0.01, 0.5);
                break;
        }
    }

    private void HandleAIDrag(double deltaX, double deltaY)
    {
        if (_activeDragHandle == DragHandle.Body)
        {
            var bbox = _viewModel!.AiBoundingBox;
            var newX = Math.Clamp(bbox.X + deltaX, 0, 1 - bbox.Width);
            var newY = Math.Clamp(bbox.Y + deltaY, 0, 1 - bbox.Height);
            _viewModel.AiBoundingBox = new Rect(newX, newY, bbox.Width, bbox.Height);
        }
    }

    private DragHandle HitTest(Point pixel)
    {
        if (_viewModel == null) return DragHandle.None;

        switch (_viewModel.Mode)
        {
            case CropMode.Rectangle:
                return HitTestRectangle(pixel);
            case CropMode.Circle:
                return HitTestCircle(pixel);
            case CropMode.AI:
                return HitTestAI(pixel);
            default:
                return DragHandle.None;
        }
    }

    private DragHandle HitTestRectangle(Point pixel)
    {
        var cropPixel = NormalizedRectToPixel(_viewModel!.CropRect);

        // Check corners first (higher priority)
        if (IsNear(pixel, cropPixel.TopLeft)) return DragHandle.TopLeft;
        if (IsNear(pixel, cropPixel.TopRight)) return DragHandle.TopRight;
        if (IsNear(pixel, cropPixel.BottomLeft)) return DragHandle.BottomLeft;
        if (IsNear(pixel, cropPixel.BottomRight)) return DragHandle.BottomRight;

        // Check edges
        if (IsNear(pixel, new Point(cropPixel.X + cropPixel.Width / 2, cropPixel.Y))) return DragHandle.Top;
        if (IsNear(pixel, new Point(cropPixel.X + cropPixel.Width / 2, cropPixel.Bottom))) return DragHandle.Bottom;
        if (IsNear(pixel, new Point(cropPixel.X, cropPixel.Y + cropPixel.Height / 2))) return DragHandle.Left;
        if (IsNear(pixel, new Point(cropPixel.Right, cropPixel.Y + cropPixel.Height / 2))) return DragHandle.Right;

        // Check inside crop area for body drag
        if (cropPixel.Contains(pixel)) return DragHandle.Body;

        return DragHandle.None;
    }

    private DragHandle HitTestCircle(Point pixel)
    {
        var displayRect = GetVideoDisplayRect();
        var center = NormalizedToPixel(_viewModel!.CircleCenter);
        var radius = _viewModel.CircleRadius * Math.Min(displayRect.Width, displayRect.Height);

        // Check radius handle
        var radiusPoint = new Point(center.X + radius, center.Y);
        if (IsNear(pixel, radiusPoint)) return DragHandle.RadiusHandle;

        // Check center
        if (IsNear(pixel, center)) return DragHandle.Body;

        // Check inside circle
        var dx = pixel.X - center.X;
        var dy = pixel.Y - center.Y;
        if (Math.Sqrt(dx * dx + dy * dy) <= radius) return DragHandle.Body;

        return DragHandle.None;
    }

    private DragHandle HitTestAI(Point pixel)
    {
        var bbox = _viewModel!.AiBoundingBox;
        if (bbox.Width <= 0) return DragHandle.None;

        var pixelRect = NormalizedRectToPixel(bbox);
        if (pixelRect.Contains(pixel)) return DragHandle.Body;

        return DragHandle.None;
    }

    private static bool IsNear(Point a, Point b)
    {
        return Math.Abs(a.X - b.X) < HitTestMargin && Math.Abs(a.Y - b.Y) < HitTestMargin;
    }

    private enum DragHandle
    {
        None, Body,
        TopLeft, TopRight, BottomLeft, BottomRight,
        Top, Bottom, Left, Right,
        RadiusHandle
    }
}
