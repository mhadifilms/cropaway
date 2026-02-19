using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using CropawayWindows.ViewModels;

namespace CropawayWindows.Views;

public partial class MainWindow : Window
{
    private MainViewModel ViewModel => (MainViewModel)DataContext;

    public MainWindow()
    {
        InitializeComponent();
        Loaded += OnLoaded;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        // Connect the MediaElement to the player ViewModel
        ViewModel.Player.SetMediaElement(VideoPlayer);
    }

    private void OnKeyDown(object sender, KeyEventArgs e)
    {
        ViewModel.HandleKeyDown(e);
    }

    /// <summary>
    /// Mouse wheel over the video preview area:
    /// - Ctrl+scroll: zoom in/out (existing behavior)
    /// - Plain scroll: step forward/backward one frame (scrub)
    /// </summary>
    private void OnVideoPreviewMouseWheel(object sender, MouseWheelEventArgs e)
    {
        bool ctrl = (Keyboard.Modifiers & ModifierKeys.Control) != 0;

        if (ctrl)
        {
            // Ctrl+scroll: zoom the video preview
            ViewModel.HandleMouseWheelZoom(e.Delta);
        }
        else
        {
            // Plain scroll: scrub through video frame-by-frame
            if (e.Delta > 0)
                ViewModel.Player.StepForward();
            else if (e.Delta < 0)
                ViewModel.Player.StepBackward();
        }

        e.Handled = true;
    }

    private void OnFileDrop(object sender, DragEventArgs e)
    {
        if (e.Data.GetDataPresent(DataFormats.FileDrop))
        {
            var files = (string[])e.Data.GetData(DataFormats.FileDrop)!;
            ViewModel.Project.HandleFileDrop(files);
        }
    }

    private void OnDragOver(object sender, DragEventArgs e)
    {
        if (e.Data.GetDataPresent(DataFormats.FileDrop))
        {
            e.Effects = DragDropEffects.Copy;
        }
        else
        {
            e.Effects = DragDropEffects.None;
        }
        e.Handled = true;
    }

    private void OnExportDropdownClick(object sender, RoutedEventArgs e)
    {
        if (sender is Button button && button.ContextMenu != null)
        {
            button.ContextMenu.PlacementTarget = button;
            button.ContextMenu.Placement = PlacementMode.Bottom;
            button.ContextMenu.IsOpen = true;
        }
    }
}
