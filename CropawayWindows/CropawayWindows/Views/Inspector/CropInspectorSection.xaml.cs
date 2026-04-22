using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using CropawayWindows.Models;
using CropawayWindows.ViewModels;

namespace CropawayWindows.Views.Inspector;

public partial class CropInspectorSection : UserControl
{
    public CropInspectorSection()
    {
        InitializeComponent();
        DataContextChanged += OnDataContextChanged;
    }

    private void OnDataContextChanged(object sender, DependencyPropertyChangedEventArgs e)
    {
        if (e.OldValue is InspectorViewModel oldVm)
            oldVm.PropertyChanged -= OnViewModelPropertyChanged;

        if (e.NewValue is InspectorViewModel newVm)
        {
            newVm.PropertyChanged += OnViewModelPropertyChanged;
            UpdateVisiblePanel(newVm.CropMode);
        }
    }

    private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName == nameof(InspectorViewModel.CropMode) && sender is InspectorViewModel vm)
        {
            UpdateVisiblePanel(vm.CropMode);
        }
    }

    private void UpdateVisiblePanel(CropMode mode)
    {
        RectangleFields.Visibility = mode == CropMode.Rectangle ? Visibility.Visible : Visibility.Collapsed;
        CircleFields.Visibility = mode == CropMode.Circle ? Visibility.Visible : Visibility.Collapsed;
        FreehandFields.Visibility = mode == CropMode.Freehand ? Visibility.Visible : Visibility.Collapsed;
        AIFields.Visibility = mode == CropMode.AI ? Visibility.Visible : Visibility.Collapsed;
    }

    /// <summary>
    /// Handles Enter key in numeric text fields to commit the value by moving focus.
    /// </summary>
    private void OnNumericKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key == Key.Enter)
        {
            var textBox = (TextBox)sender;
            // Move focus away to trigger LostFocus binding update
            textBox.MoveFocus(new TraversalRequest(FocusNavigationDirection.Next));
            e.Handled = true;
        }
        else if (e.Key == Key.Escape)
        {
            // Cancel edit by clearing focus
            Keyboard.ClearFocus();
            e.Handled = true;
        }
    }
}
