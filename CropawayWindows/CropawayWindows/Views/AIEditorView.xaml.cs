using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using CropawayWindows.Models;
using CropawayWindows.Services;
using CropawayWindows.ViewModels;

namespace CropawayWindows.Views;

public partial class AIEditorView : UserControl
{
    private CropEditorViewModel? ViewModel => DataContext as CropEditorViewModel;

    public AIEditorView()
    {
        InitializeComponent();
        Loaded += OnLoaded;
        DataContextChanged += OnDataContextChanged;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        UpdateApiKeyStatus();
        UpdateResultsDisplay();

        // Subscribe to FalAI status changes
        FalAIService.Instance.StatusChanged += OnFalAIStatusChanged;
    }

    private void OnDataContextChanged(object sender, DependencyPropertyChangedEventArgs e)
    {
        if (e.OldValue is CropEditorViewModel oldVM)
        {
            oldVM.PropertyChanged -= OnViewModelPropertyChanged;
        }

        if (e.NewValue is CropEditorViewModel newVM)
        {
            newVM.PropertyChanged += OnViewModelPropertyChanged;
            UpdateResultsDisplay();
        }
    }

    private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(CropEditorViewModel.AiBoundingBox))
        {
            Dispatcher.Invoke(UpdateResultsDisplay);
        }
    }

    /// <summary>
    /// Updates the API key status indicator (green dot = configured, red = missing).
    /// </summary>
    private void UpdateApiKeyStatus()
    {
        bool hasKey = FalAIService.Instance.HasAPIKey;

        if (hasKey)
        {
            ApiKeyStatusDot.Fill = new SolidColorBrush(Color.FromRgb(0x16, 0xC6, 0x0C));
            ApiKeyStatusText.Text = "API key configured";
            ApiKeyStatusText.Foreground = FindResource("TextSecondaryBrush") as Brush;
            ApiKeyStatusBorder.Background = new SolidColorBrush(Color.FromArgb(0x20, 0x16, 0xC6, 0x0C));
        }
        else
        {
            ApiKeyStatusDot.Fill = new SolidColorBrush(Color.FromRgb(0xF4, 0x47, 0x47));
            ApiKeyStatusText.Text = "No API key - click the gear icon to configure";
            ApiKeyStatusText.Foreground = FindResource("TextSecondaryBrush") as Brush;
            ApiKeyStatusBorder.Background = new SolidColorBrush(Color.FromArgb(0x20, 0xF4, 0x47, 0x47));
        }
    }

    /// <summary>
    /// Updates the results panel with bounding box info if available.
    /// </summary>
    private void UpdateResultsDisplay()
    {
        if (ViewModel == null) return;

        var bbox = ViewModel.AiBoundingBox;
        bool hasResults = bbox.Width > 0 && bbox.Height > 0;

        ResultsPanel.Visibility = hasResults ? Visibility.Visible : Visibility.Collapsed;
        ClearResultsButton.Visibility = hasResults ? Visibility.Visible : Visibility.Collapsed;

        if (hasResults)
        {
            BBoxXLabel.Text = $"X: {bbox.X:F3}";
            BBoxYLabel.Text = $"Y: {bbox.Y:F3}";
            BBoxWLabel.Text = $"W: {bbox.Width:F3}";
            BBoxHLabel.Text = $"H: {bbox.Height:F3}";
        }
    }

    // -- Interaction mode handlers --

    private void OnInteractionModePoint(object sender, RoutedEventArgs e)
    {
        if (ViewModel != null)
            ViewModel.AiInteractionMode = AIInteractionMode.Point;
    }

    private void OnInteractionModeBox(object sender, RoutedEventArgs e)
    {
        if (ViewModel != null)
            ViewModel.AiInteractionMode = AIInteractionMode.Box;
    }

    private void OnInteractionModeText(object sender, RoutedEventArgs e)
    {
        if (ViewModel != null)
            ViewModel.AiInteractionMode = AIInteractionMode.Text;
    }

    // -- API key setup --

    private void OnSetupApiKeyClick(object sender, RoutedEventArgs e)
    {
        var dialog = new FalAISetupView();
        dialog.Owner = Window.GetWindow(this);
        dialog.ShowDialog();
        UpdateApiKeyStatus();
    }

    // -- Track object --

    private async void OnTrackObjectClick(object sender, RoutedEventArgs e)
    {
        if (ViewModel == null) return;

        if (!FalAIService.Instance.HasAPIKey)
        {
            SetStatus("\uE7BA", "Please configure your fal.ai API key first.", isError: true);
            return;
        }

        // Get the current video info from MainViewModel
        var mainWindow = Window.GetWindow(this);
        var mainVM = mainWindow?.DataContext as MainViewModel;
        var video = mainVM?.Project.SelectedVideo;

        if (video == null)
        {
            SetStatus("\uE7BA", "No video selected.", isError: true);
            return;
        }

        // Disable button during processing
        TrackButton.IsEnabled = false;
        AIProgressBar.Visibility = Visibility.Visible;

        try
        {
            string? prompt = string.IsNullOrWhiteSpace(ViewModel.AiTextPrompt)
                ? null
                : ViewModel.AiTextPrompt;

            // Determine point prompt based on interaction mode
            Point? pointPrompt = null;
            if (ViewModel.AiInteractionMode == AIInteractionMode.Point &&
                ViewModel.AiPromptPoints.Count > 0)
            {
                var firstPoint = ViewModel.AiPromptPoints[0];
                pointPrompt = new Point(firstPoint.Position.X, firstPoint.Position.Y);
            }

            SetStatus("\uE895", "Uploading video to fal.ai...", isError: false);

            var result = await FalAIService.Instance.TrackObjectAsync(
                video.SourcePath,
                prompt,
                pointPrompt,
                video.Metadata.Width,
                video.Metadata.Height,
                video.Metadata.FrameRate);

            // Apply results - set bounding box from first frame
            if (result.BoundingBoxes.TryGetValue(0, out var firstBox))
            {
                ViewModel.AiBoundingBox = firstBox;
            }

            // Convert tracking results to keyframes
            if (result.BoundingBoxes.Count > 0 && mainVM != null)
            {
                double frameRate = video.Metadata.FrameRate > 0 ? video.Metadata.FrameRate : 30.0;
                mainVM.Keyframes.ImportAITrackingResults(result.BoundingBoxes, frameRate);
            }

            SetStatus("\uE73E", $"Tracking complete - {result.BoundingBoxes.Count} frames tracked", isError: false);
            ResultsFrameCount.Text = $"{result.FrameCount} frames";
            UpdateResultsDisplay();
        }
        catch (FalAIException ex)
        {
            SetStatus("\uE783", $"Error: {ex.Message}", isError: true);
        }
        catch (Exception ex)
        {
            SetStatus("\uE783", $"Unexpected error: {ex.Message}", isError: true);
        }
        finally
        {
            TrackButton.IsEnabled = true;
            AIProgressBar.Visibility = Visibility.Collapsed;
        }
    }

    /// <summary>
    /// Handles status updates from the FalAI service (runs on background thread).
    /// </summary>
    private void OnFalAIStatusChanged(FalAIStatus status, double progress)
    {
        Dispatcher.Invoke(() =>
        {
            string statusText = status switch
            {
                FalAIStatus.Uploading => $"Uploading video... {progress:P0}",
                FalAIStatus.Processing => "Processing on fal.ai servers...",
                FalAIStatus.Downloading => "Downloading results...",
                FalAIStatus.Extracting => "Extracting tracking data...",
                FalAIStatus.Completed => "Tracking complete",
                FalAIStatus.Error => $"Error: {FalAIService.Instance.LastError}",
                _ => ""
            };

            bool isError = status == FalAIStatus.Error;
            string icon = status switch
            {
                FalAIStatus.Uploading => "\uE895",
                FalAIStatus.Processing => "\uE895",
                FalAIStatus.Downloading => "\uE896",
                FalAIStatus.Extracting => "\uE895",
                FalAIStatus.Completed => "\uE73E",
                FalAIStatus.Error => "\uE783",
                _ => ""
            };

            SetStatus(icon, statusText, isError);
        });
    }

    /// <summary>
    /// Updates the status display area with an icon, message, and optional error styling.
    /// </summary>
    private void SetStatus(string iconGlyph, string message, bool isError)
    {
        StatusIcon.Text = iconGlyph;
        StatusText.Text = message;

        // Show or hide the status border based on whether there is a message
        StatusBorder.Visibility = string.IsNullOrEmpty(message)
            ? Visibility.Collapsed
            : Visibility.Visible;

        if (isError)
        {
            StatusIcon.Foreground = FindResource("ErrorBrush") as Brush;
            StatusText.Foreground = FindResource("ErrorBrush") as Brush;
        }
        else
        {
            StatusIcon.Foreground = FindResource("TextSecondaryBrush") as Brush;
            StatusText.Foreground = FindResource("TextSecondaryBrush") as Brush;
        }
    }

    // -- Clear results --

    private void OnClearResultsClick(object sender, RoutedEventArgs e)
    {
        ViewModel?.ClearAIMask();
        SetStatus("", "", isError: false);
        UpdateResultsDisplay();
    }
}
