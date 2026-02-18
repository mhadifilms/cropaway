using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using CropawayWindows.Models;
using CropawayWindows.ViewModels;

namespace CropawayWindows.Views;

public partial class SequencesTabView : UserControl
{
    private TimelineViewModel? ViewModel => DataContext as TimelineViewModel;

    public SequencesTabView()
    {
        InitializeComponent();
    }

    // -- Inline rename support --

    private void OnNameDoubleClick(object sender, MouseButtonEventArgs e)
    {
        if (e.ClickCount == 2 && sender is TextBlock textBlock)
        {
            StartRename(textBlock);
            e.Handled = true;
        }
    }

    private void StartRename(TextBlock nameDisplay)
    {
        // Find the sibling TextBox editor within the same parent StackPanel
        var parent = nameDisplay.Parent as StackPanel;
        if (parent == null) return;

        var nameEditor = parent.Children.OfType<TextBox>().FirstOrDefault();
        if (nameEditor == null) return;

        nameDisplay.Visibility = Visibility.Collapsed;
        nameEditor.Visibility = Visibility.Visible;
        nameEditor.Focus();
        nameEditor.SelectAll();
    }

    private void OnNameEditorLostFocus(object sender, RoutedEventArgs e)
    {
        CommitRename(sender as TextBox);
    }

    private void OnNameEditorKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter)
        {
            CommitRename(sender as TextBox);
            e.Handled = true;
        }
        else if (e.Key == Key.Escape)
        {
            CancelRename(sender as TextBox);
            e.Handled = true;
        }
    }

    private void CommitRename(TextBox? editor)
    {
        if (editor == null) return;

        var parent = editor.Parent as StackPanel;
        if (parent == null) return;

        var nameDisplay = parent.Children.OfType<TextBlock>().FirstOrDefault();
        if (nameDisplay == null) return;

        // The binding already updated the Name property through UpdateSourceTrigger=PropertyChanged
        // Just switch back to display mode
        editor.Visibility = Visibility.Collapsed;
        nameDisplay.Visibility = Visibility.Visible;
    }

    private void CancelRename(TextBox? editor)
    {
        if (editor == null) return;

        var parent = editor.Parent as StackPanel;
        if (parent == null) return;

        var nameDisplay = parent.Children.OfType<TextBlock>().FirstOrDefault();
        if (nameDisplay == null) return;

        // Restore original value from the TextBlock (revert binding)
        var timeline = editor.DataContext as Timeline;
        if (timeline != null)
        {
            editor.Text = timeline.Name;
        }

        editor.Visibility = Visibility.Collapsed;
        nameDisplay.Visibility = Visibility.Visible;
    }

    // -- Delete sequence --

    private void OnDeleteSequenceClick(object sender, RoutedEventArgs e)
    {
        if (ViewModel == null) return;

        var button = sender as Button;
        var timeline = button?.DataContext as Timeline;
        if (timeline != null)
        {
            ViewModel.DeleteSequenceCommand.Execute(timeline);
        }
    }

    // -- Context menu handlers --

    private void OnRenameClick(object sender, RoutedEventArgs e)
    {
        var timeline = GetContextMenuTimeline(sender);
        if (timeline == null) return;

        // Select the timeline first
        if (ViewModel != null)
        {
            ViewModel.ActiveTimeline = timeline;
        }

        // Find the ListBoxItem for this timeline and trigger rename
        // We do this by finding the TextBlock in the visual tree
        var listBox = FindListBox();
        if (listBox == null) return;

        var container = listBox.ItemContainerGenerator.ContainerFromItem(timeline) as ListBoxItem;
        if (container == null) return;

        var nameDisplay = FindVisualChild<TextBlock>(container, "NameDisplay");
        if (nameDisplay != null)
        {
            StartRename(nameDisplay);
        }
    }

    private void OnDuplicateClick(object sender, RoutedEventArgs e)
    {
        if (ViewModel == null) return;

        var timeline = GetContextMenuTimeline(sender);
        if (timeline != null)
        {
            ViewModel.DuplicateSequenceCommand.Execute(timeline);
        }
    }

    private void OnDeleteContextClick(object sender, RoutedEventArgs e)
    {
        if (ViewModel == null) return;

        var timeline = GetContextMenuTimeline(sender);
        if (timeline != null)
        {
            ViewModel.DeleteSequenceCommand.Execute(timeline);
        }
    }

    // -- Helpers --

    private static Timeline? GetContextMenuTimeline(object sender)
    {
        var menuItem = sender as MenuItem;
        var contextMenu = menuItem?.Parent as ContextMenu;
        return contextMenu?.DataContext as Timeline;
    }

    private ListBox? FindListBox()
    {
        return FindVisualChild<ListBox>(this);
    }

    private static T? FindVisualChild<T>(DependencyObject parent, string? name = null) where T : FrameworkElement
    {
        for (int i = 0; i < System.Windows.Media.VisualTreeHelper.GetChildrenCount(parent); i++)
        {
            var child = System.Windows.Media.VisualTreeHelper.GetChild(parent, i);
            if (child is T typedChild && (name == null || typedChild.Name == name))
                return typedChild;

            var result = FindVisualChild<T>(child, name);
            if (result != null)
                return result;
        }
        return null;
    }
}
