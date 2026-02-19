using System.Collections.Specialized;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using CropawayWindows.Models;
using CropawayWindows.ViewModels;

namespace CropawayWindows.Views;

public partial class VideoSidebarView : UserControl
{
    private Point _dragStartPoint;
    private bool _isDragging;

    private MainViewModel? MainVM => DataContext as MainViewModel;
    private ProjectViewModel? ProjectVM => MainVM?.Project;

    public VideoSidebarView()
    {
        InitializeComponent();
        DataContextChanged += OnDataContextChanged;
    }

    private void OnDataContextChanged(object sender, DependencyPropertyChangedEventArgs e)
    {
        if (e.OldValue is MainViewModel oldMainVM)
        {
            oldMainVM.Project.Videos.CollectionChanged -= OnVideosCollectionChanged;
        }
        else if (e.OldValue is ProjectViewModel oldVM)
        {
            oldVM.Videos.CollectionChanged -= OnVideosCollectionChanged;
        }

        if (e.NewValue is MainViewModel newMainVM)
        {
            newMainVM.Project.Videos.CollectionChanged += OnVideosCollectionChanged;
            UpdateEmptyState(newMainVM.Project.Videos.Count);
        }
        else if (e.NewValue is ProjectViewModel newVM)
        {
            newVM.Videos.CollectionChanged += OnVideosCollectionChanged;
            UpdateEmptyState(newVM.Videos.Count);
        }
    }

    private void OnVideosCollectionChanged(object? sender, NotifyCollectionChangedEventArgs e)
    {
        UpdateEmptyState(ProjectVM?.Videos.Count ?? 0);
    }

    private void UpdateEmptyState(int count)
    {
        if (EmptyStatePanel != null)
        {
            EmptyStatePanel.Visibility = count == 0 ? Visibility.Visible : Visibility.Collapsed;
        }
    }

    // -- Drag-drop reordering support --

    private void OnListPreviewMouseDown(object sender, MouseButtonEventArgs e)
    {
        _dragStartPoint = e.GetPosition(null);
        _isDragging = false;
    }

    private void OnListPreviewMouseMove(object sender, MouseEventArgs e)
    {
        if (e.LeftButton != MouseButtonState.Pressed) return;

        Point currentPos = e.GetPosition(null);
        Vector diff = _dragStartPoint - currentPos;

        // Check minimum drag distance to avoid accidental drags
        if (Math.Abs(diff.X) < SystemParameters.MinimumHorizontalDragDistance &&
            Math.Abs(diff.Y) < SystemParameters.MinimumVerticalDragDistance)
        {
            return;
        }

        if (_isDragging) return;

        // Find the ListBoxItem being dragged
        var listBox = sender as ListBox;
        if (listBox == null) return;

        var element = e.OriginalSource as DependencyObject;
        var listBoxItem = FindAncestor<ListBoxItem>(element);
        if (listBoxItem == null) return;

        var videoItem = listBoxItem.DataContext as VideoItem;
        if (videoItem == null) return;

        _isDragging = true;

        var data = new DataObject("VideoItem", videoItem);
        DragDrop.DoDragDrop(listBoxItem, data, DragDropEffects.Move);

        _isDragging = false;
    }

    private void OnListDragOver(object sender, DragEventArgs e)
    {
        if (e.Data.GetDataPresent("VideoItem"))
        {
            e.Effects = DragDropEffects.Move;
        }
        else if (e.Data.GetDataPresent(DataFormats.FileDrop))
        {
            e.Effects = DragDropEffects.Copy;
        }
        else
        {
            e.Effects = DragDropEffects.None;
        }
        e.Handled = true;
    }

    private void OnListDrop(object sender, DragEventArgs e)
    {
        if (ProjectVM == null) return;

        // Handle reordering within the list
        if (e.Data.GetDataPresent("VideoItem"))
        {
            var draggedItem = e.Data.GetData("VideoItem") as VideoItem;
            if (draggedItem == null) return;

            // Find the target item under the drop position
            var element = e.OriginalSource as DependencyObject;
            var listBoxItem = FindAncestor<ListBoxItem>(element);

            if (listBoxItem != null)
            {
                var targetItem = listBoxItem.DataContext as VideoItem;
                if (targetItem != null && targetItem != draggedItem)
                {
                    int oldIndex = ProjectVM.Videos.IndexOf(draggedItem);
                    int newIndex = ProjectVM.Videos.IndexOf(targetItem);

                    if (oldIndex >= 0 && newIndex >= 0 && oldIndex != newIndex)
                    {
                        ProjectVM.Videos.Move(oldIndex, newIndex);
                    }
                }
            }

            e.Handled = true;
        }
        // Handle file drops from explorer
        else if (e.Data.GetDataPresent(DataFormats.FileDrop))
        {
            var files = (string[])e.Data.GetData(DataFormats.FileDrop)!;
            ProjectVM.HandleFileDrop(files);
            e.Handled = true;
        }
    }

    // -- Context menu handlers --

    private void OnRemoveVideoClick(object sender, RoutedEventArgs e)
    {
        if (ProjectVM == null) return;

        var menuItem = sender as MenuItem;
        var contextMenu = menuItem?.Parent as ContextMenu;
        var videoItem = contextMenu?.DataContext as VideoItem;

        if (videoItem != null)
        {
            // Select the item first, then remove
            ProjectVM.SelectedVideo = videoItem;
            ProjectVM.RemoveSelectedVideoCommand.Execute(null);
        }
    }

    private void OnExportVideoClick(object sender, RoutedEventArgs e)
    {
        var videoItem = GetContextMenuVideoItem(sender);
        if (videoItem == null || MainVM == null) return;

        MainVM.Project.SelectedVideo = videoItem;
        MainVM.ExportCurrentVideoCommand.Execute(null);
    }

    private void OnExportJsonClick(object sender, RoutedEventArgs e)
    {
        var videoItem = GetContextMenuVideoItem(sender);
        if (videoItem == null || MainVM == null) return;

        MainVM.Project.SelectedVideo = videoItem;
        MainVM.ExportBoundingBoxJsonCommand.Execute(null);
    }

    private void OnCopyCropSettingsClick(object sender, RoutedEventArgs e)
    {
        var videoItem = GetContextMenuVideoItem(sender);
        if (videoItem == null || MainVM == null) return;

        MainVM.Project.SelectedVideo = videoItem;
        MainVM.CopyCropSettingsCommand.Execute(null);
    }

    private void OnPasteCropSettingsClick(object sender, RoutedEventArgs e)
    {
        var videoItem = GetContextMenuVideoItem(sender);
        if (videoItem == null || MainVM == null) return;

        MainVM.Project.SelectedVideo = videoItem;
        MainVM.PasteCropSettingsCommand.Execute(null);
    }

    private void OnResetCropClick(object sender, RoutedEventArgs e)
    {
        var videoItem = GetContextMenuVideoItem(sender);
        if (videoItem == null || MainVM == null) return;

        MainVM.Project.SelectedVideo = videoItem;
        MainVM.ResetCropCommand.Execute(null);
    }

    private void OnRevealInExplorerClick(object sender, RoutedEventArgs e)
    {
        var videoItem = GetContextMenuVideoItem(sender);
        if (videoItem == null) return;

        var sourcePath = videoItem.SourcePath;
        if (!string.IsNullOrEmpty(sourcePath) && File.Exists(sourcePath))
        {
            Process.Start("explorer.exe", $"/select,\"{sourcePath}\"");
        }
    }

    private void OnListItemDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (sender is not ListBoxItem listBoxItem) return;
        if (listBoxItem.DataContext is not VideoItem videoItem) return;
        if (MainVM == null) return;

        // Select the video and start playback
        MainVM.Project.SelectedVideo = videoItem;
        MainVM.Player.Play();
        e.Handled = true;
    }

    // -- Helpers --

    private static VideoItem? GetContextMenuVideoItem(object sender)
    {
        var menuItem = sender as MenuItem;
        var contextMenu = menuItem?.Parent as ContextMenu;
        return contextMenu?.DataContext as VideoItem;
    }

    private static T? FindAncestor<T>(DependencyObject? current) where T : DependencyObject
    {
        while (current != null)
        {
            if (current is T match)
                return match;
            current = VisualTreeHelper.GetParent(current);
        }
        return null;
    }
}
