using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using CropawayWindows.Models;
using CropawayWindows.ViewModels;

namespace CropawayWindows.Views;

public partial class CropInputPanel : UserControl
{
    private CropEditorViewModel? _editor;
    private double _videoWidth;
    private double _videoHeight;
    private bool _isUpdating;
    private bool _aspectLocked;
    private double _lockedAspectRatio; // width/height

    public CropInputPanel()
    {
        InitializeComponent();
        Loaded += OnLoaded;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        // Find the main view model to get video dimensions
        var mainWindow = Window.GetWindow(this);
        var mainVM = mainWindow?.DataContext as MainViewModel;
        if (mainVM == null) return;

        _editor = mainVM.CropEditor;

        // Listen for crop/mode changes
        _editor.PropertyChanged += (s, args) =>
        {
            if (_isUpdating) return;
            switch (args.PropertyName)
            {
                case nameof(CropEditorViewModel.Mode):
                    UpdateVisiblePanel();
                    RefreshValues();
                    break;
                case nameof(CropEditorViewModel.CropRect):
                case nameof(CropEditorViewModel.CircleCenter):
                case nameof(CropEditorViewModel.CircleRadius):
                case nameof(CropEditorViewModel.AiBoundingBox):
                case nameof(CropEditorViewModel.FreehandPoints):
                    RefreshValues();
                    break;
            }
        };

        // Listen for video size changes
        mainVM.Player.PropertyChanged += (s, args) =>
        {
            if (args.PropertyName == nameof(VideoPlayerViewModel.VideoSize))
            {
                _videoWidth = mainVM.Player.VideoSize.Width;
                _videoHeight = mainVM.Player.VideoSize.Height;
                RefreshValues();
            }
        };

        // Listen for video selection changes
        mainVM.Project.PropertyChanged += (s, args) =>
        {
            if (args.PropertyName == nameof(ProjectViewModel.SelectedVideo))
            {
                var video = mainVM.Project.SelectedVideo;
                if (video != null)
                {
                    _videoWidth = video.Metadata.Width;
                    _videoHeight = video.Metadata.Height;
                }
                RefreshValues();
            }
        };

        // Initial state
        var selectedVideo = mainVM.Project.SelectedVideo;
        if (selectedVideo != null)
        {
            _videoWidth = selectedVideo.Metadata.Width;
            _videoHeight = selectedVideo.Metadata.Height;
        }

        UpdateVisiblePanel();
        RefreshValues();
    }

    private void UpdateVisiblePanel()
    {
        if (_editor == null) return;

        RectangleInputs.Visibility = _editor.Mode == CropMode.Rectangle ? Visibility.Visible : Visibility.Collapsed;
        CircleInputs.Visibility = _editor.Mode == CropMode.Circle ? Visibility.Visible : Visibility.Collapsed;
        AIInputs.Visibility = _editor.Mode == CropMode.AI ? Visibility.Visible : Visibility.Collapsed;
        FreehandInputs.Visibility = _editor.Mode == CropMode.Freehand ? Visibility.Visible : Visibility.Collapsed;
    }

    private void RefreshValues()
    {
        if (_editor == null || _videoWidth <= 0 || _videoHeight <= 0) return;

        _isUpdating = true;
        try
        {
            switch (_editor.Mode)
            {
                case CropMode.Rectangle:
                    RefreshRectangleValues();
                    break;
                case CropMode.Circle:
                    RefreshCircleValues();
                    break;
                case CropMode.AI:
                    RefreshAIValues();
                    break;
                case CropMode.Freehand:
                    RefreshFreehandValues();
                    break;
            }
        }
        finally
        {
            _isUpdating = false;
        }
    }

    private void RefreshRectangleValues()
    {
        var rect = _editor!.CropRect;
        RectX.Text = ((int)Math.Round(rect.X * _videoWidth)).ToString();
        RectY.Text = ((int)Math.Round(rect.Y * _videoHeight)).ToString();
        RectW.Text = ((int)Math.Round(rect.Width * _videoWidth)).ToString();
        RectH.Text = ((int)Math.Round(rect.Height * _videoHeight)).ToString();
    }

    private void RefreshCircleValues()
    {
        CircleCX.Text = ((int)Math.Round(_editor!.CircleCenter.X * _videoWidth)).ToString();
        CircleCY.Text = ((int)Math.Round(_editor.CircleCenter.Y * _videoHeight)).ToString();
        CircleR.Text = ((int)Math.Round(_editor.CircleRadius * Math.Min(_videoWidth, _videoHeight))).ToString();
    }

    private void RefreshAIValues()
    {
        var bbox = _editor!.AiBoundingBox;
        if (bbox.Width <= 0 || bbox.Height <= 0)
        {
            AIBboxText.Text = "No tracking data";
        }
        else
        {
            var x = (int)Math.Round(bbox.X * _videoWidth);
            var y = (int)Math.Round(bbox.Y * _videoHeight);
            var w = (int)Math.Round(bbox.Width * _videoWidth);
            var h = (int)Math.Round(bbox.Height * _videoHeight);
            AIBboxText.Text = $"{x}, {y} - {w} x {h} px";
        }
    }

    private void RefreshFreehandValues()
    {
        var points = _editor!.FreehandPoints;
        if (points.Count < 3)
        {
            FreehandBoundsText.Text = "No mask drawn";
            FreehandPointCount.Text = "";
        }
        else
        {
            var minX = points.Min(p => p.X);
            var maxX = points.Max(p => p.X);
            var minY = points.Min(p => p.Y);
            var maxY = points.Max(p => p.Y);
            var w = (int)Math.Round((maxX - minX) * _videoWidth);
            var h = (int)Math.Round((maxY - minY) * _videoHeight);
            FreehandBoundsText.Text = $"{w} x {h} px";
            FreehandPointCount.Text = $"({points.Count} points)";
        }
    }

    private void OnTextBoxKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter)
        {
            // Apply value on Enter
            if (_editor?.Mode == CropMode.Rectangle)
                ApplyRectangleValues();
            else if (_editor?.Mode == CropMode.Circle)
                ApplyCircleValues();

            e.Handled = true;
            // Move focus away
            Keyboard.ClearFocus();
        }
        else if (e.Key == Key.Escape)
        {
            RefreshValues(); // Revert
            e.Handled = true;
            Keyboard.ClearFocus();
        }
    }

    private void OnRectValueChanged(object sender, RoutedEventArgs e)
    {
        if (_isUpdating || _editor == null) return;
        ApplyRectangleValues();
    }

    private void OnCircleValueChanged(object sender, RoutedEventArgs e)
    {
        if (_isUpdating || _editor == null) return;
        ApplyCircleValues();
    }

    private void ApplyRectangleValues()
    {
        if (_editor == null || _videoWidth <= 0 || _videoHeight <= 0) return;

        if (!int.TryParse(RectX.Text, out int x) ||
            !int.TryParse(RectY.Text, out int y) ||
            !int.TryParse(RectW.Text, out int w) ||
            !int.TryParse(RectH.Text, out int h))
        {
            RefreshValues();
            return;
        }

        // Clamp to valid range
        x = Math.Clamp(x, 0, (int)_videoWidth - 1);
        y = Math.Clamp(y, 0, (int)_videoHeight - 1);
        w = Math.Clamp(w, 1, (int)_videoWidth - x);
        h = Math.Clamp(h, 1, (int)_videoHeight - y);

        // Apply aspect ratio lock
        if (_aspectLocked && _lockedAspectRatio > 0)
        {
            // Adjust height to match locked aspect ratio
            h = (int)Math.Round(w / _lockedAspectRatio);
            h = Math.Clamp(h, 1, (int)_videoHeight - y);
            // Re-adjust width if height was clamped
            w = (int)Math.Round(h * _lockedAspectRatio);
            w = Math.Clamp(w, 1, (int)_videoWidth - x);
        }

        // Convert to normalized
        _isUpdating = true;
        _editor.CropRect = new Rect(
            x / _videoWidth,
            y / _videoHeight,
            w / _videoWidth,
            h / _videoHeight);
        _isUpdating = false;

        RefreshValues();
    }

    private void ApplyCircleValues()
    {
        if (_editor == null || _videoWidth <= 0 || _videoHeight <= 0) return;

        if (!int.TryParse(CircleCX.Text, out int cx) ||
            !int.TryParse(CircleCY.Text, out int cy) ||
            !int.TryParse(CircleR.Text, out int r))
        {
            RefreshValues();
            return;
        }

        cx = Math.Clamp(cx, 0, (int)_videoWidth);
        cy = Math.Clamp(cy, 0, (int)_videoHeight);
        r = Math.Clamp(r, 1, (int)(Math.Min(_videoWidth, _videoHeight) / 2));

        _isUpdating = true;
        _editor.CircleCenter = new Point(cx / _videoWidth, cy / _videoHeight);
        _editor.CircleRadius = r / Math.Min(_videoWidth, _videoHeight);
        _isUpdating = false;

        RefreshValues();
    }

    private void OnAspectLockChanged(object sender, RoutedEventArgs e)
    {
        _aspectLocked = AspectLockToggle.IsChecked == true;
        if (_aspectLocked && _editor != null && _videoWidth > 0 && _videoHeight > 0)
        {
            var rect = _editor.CropRect;
            var w = rect.Width * _videoWidth;
            var h = rect.Height * _videoHeight;
            _lockedAspectRatio = h > 0 ? w / h : 1.0;
        }
    }

    private void OnPresetChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isUpdating || _editor == null || _videoWidth <= 0 || _videoHeight <= 0) return;
        if (PresetCombo.SelectedItem is not ComboBoxItem item) return;

        var preset = item.Content?.ToString();
        if (preset == null || preset == "Custom") return;

        double targetRatio = preset switch
        {
            "16:9" => 16.0 / 9.0,
            "4:3" => 4.0 / 3.0,
            "1:1" => 1.0,
            "9:16" => 9.0 / 16.0,
            "21:9" => 21.0 / 9.0,
            "2.35:1" => 2.35,
            _ => 0
        };

        if (targetRatio <= 0) return;

        // Calculate new crop rect centered, fitting within video
        double vidRatio = _videoWidth / _videoHeight;
        double newW, newH;

        if (targetRatio > vidRatio)
        {
            // Crop is wider than video ratio - fit by width
            newW = 1.0;
            newH = (1.0 / targetRatio) * (_videoWidth / _videoHeight);
            newH = Math.Min(newH, 1.0);
        }
        else
        {
            // Crop is taller - fit by height
            newH = 1.0;
            newW = targetRatio * (_videoHeight / _videoWidth);
            newW = Math.Min(newW, 1.0);
        }

        double newX = (1.0 - newW) / 2.0;
        double newY = (1.0 - newH) / 2.0;

        _isUpdating = true;
        _editor.CropRect = new Rect(newX, newY, newW, newH);
        _isUpdating = false;

        // Lock to this aspect ratio
        _aspectLocked = true;
        AspectLockToggle.IsChecked = true;
        _lockedAspectRatio = targetRatio;

        RefreshValues();
    }
}
