using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using CropawayWindows.ViewModels;

namespace CropawayWindows.Views;

public partial class VideoPlayerControlsView : UserControl
{
    private bool _isScrubbing;

    private MainViewModel? ViewModel => DataContext as MainViewModel;

    public VideoPlayerControlsView()
    {
        InitializeComponent();
    }

    /// <summary>
    /// Pause playback when the user starts dragging the scrubber thumb.
    /// </summary>
    private void OnScrubberDragStarted(object sender, DragStartedEventArgs e)
    {
        _isScrubbing = true;

        if (ViewModel?.Player.IsPlaying == true)
        {
            ViewModel.Player.Pause();
        }
    }

    /// <summary>
    /// Seek to the final position when the user releases the scrubber thumb.
    /// </summary>
    private void OnScrubberDragCompleted(object sender, DragCompletedEventArgs e)
    {
        _isScrubbing = false;

        if (ViewModel?.Player != null)
        {
            ViewModel.Player.Seek(PositionSlider.Value);
        }
    }

    /// <summary>
    /// While scrubbing, update the player position in real-time for frame-accurate preview.
    /// </summary>
    private void OnScrubberValueChanged(object sender, RoutedPropertyChangedEventArgs<double> e)
    {
        if (_isScrubbing && ViewModel?.Player != null)
        {
            ViewModel.Player.Seek(e.NewValue);
        }
    }

    /// <summary>
    /// Toggle between timecode and frame count display when the time label is clicked.
    /// </summary>
    private void OnTimeDisplayClick(object sender, MouseButtonEventArgs e)
    {
        ViewModel?.Player.ToggleTimeDisplay();
    }
}
