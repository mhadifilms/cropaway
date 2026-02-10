using System.Windows;
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
}
