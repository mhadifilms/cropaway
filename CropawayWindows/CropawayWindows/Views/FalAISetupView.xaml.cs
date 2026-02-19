using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using CropawayWindows.Services;

namespace CropawayWindows.Views;

public partial class FalAISetupView : Window
{
    private bool _isRevealed;

    public FalAISetupView()
    {
        InitializeComponent();
        Loaded += OnLoaded;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        // Load existing key if present
        string? existingKey = FalAIService.Instance.GetAPIKey();
        if (!string.IsNullOrWhiteSpace(existingKey))
        {
            ApiKeyPasswordBox.Password = existingKey;
            ApiKeyTextBox.Text = existingKey;
            RemoveButton.IsEnabled = true;
            ValidateKey(existingKey);
        }
        else
        {
            SetValidation(ValidationState.Empty);
        }

        ApiKeyPasswordBox.Focus();
    }

    // -- Reveal / hide toggle --

    private void OnRevealToggle(object sender, RoutedEventArgs e)
    {
        _isRevealed = !_isRevealed;

        if (_isRevealed)
        {
            // Show plain text, hide password box
            ApiKeyTextBox.Text = ApiKeyPasswordBox.Password;
            ApiKeyPasswordBox.Visibility = Visibility.Collapsed;
            ApiKeyTextBox.Visibility = Visibility.Visible;
            RevealIcon.Text = "\uED1A"; // Eye off icon
            ApiKeyTextBox.Focus();
            ApiKeyTextBox.CaretIndex = ApiKeyTextBox.Text.Length;
        }
        else
        {
            // Show password box, hide plain text
            ApiKeyPasswordBox.Password = ApiKeyTextBox.Text;
            ApiKeyTextBox.Visibility = Visibility.Collapsed;
            ApiKeyPasswordBox.Visibility = Visibility.Visible;
            RevealIcon.Text = "\uE7B3"; // Eye icon
            ApiKeyPasswordBox.Focus();
        }
    }

    // -- Input change handlers --

    private void OnPasswordChanged(object sender, RoutedEventArgs e)
    {
        string key = ApiKeyPasswordBox.Password;
        ValidateKey(key);
    }

    private void OnTextChanged(object sender, TextChangedEventArgs e)
    {
        string key = ApiKeyTextBox.Text;
        ValidateKey(key);
    }

    private void ValidateKey(string key)
    {
        if (string.IsNullOrWhiteSpace(key))
        {
            SetValidation(ValidationState.Empty);
            SaveButton.IsEnabled = false;
        }
        else if (FalAIService.IsValidAPIKeyFormat(key))
        {
            SetValidation(ValidationState.Valid);
            SaveButton.IsEnabled = true;
        }
        else
        {
            SetValidation(ValidationState.Invalid);
            SaveButton.IsEnabled = false;
        }
    }

    // -- Validation display --

    private enum ValidationState { Empty, Valid, Invalid }

    private void SetValidation(ValidationState state)
    {
        var successBrush = new SolidColorBrush(Color.FromRgb(0x16, 0xC6, 0x0C));
        var errorBrush = FindResource("ErrorBrush") as Brush
            ?? new SolidColorBrush(Color.FromRgb(0xF4, 0x47, 0x47));
        var secondaryBrush = FindResource("TextSecondaryBrush") as Brush
            ?? new SolidColorBrush(Color.FromRgb(0xA0, 0xA0, 0xA0));

        switch (state)
        {
            case ValidationState.Empty:
                ValidationIcon.Text = "\uE946"; // Info
                ValidationIcon.Foreground = secondaryBrush;
                ValidationText.Text = "Enter your fal.ai API key (minimum 20 characters)";
                ValidationText.Foreground = secondaryBrush;
                break;

            case ValidationState.Valid:
                ValidationIcon.Text = "\uE73E"; // Check
                ValidationIcon.Foreground = successBrush;
                ValidationText.Text = "Valid API key format";
                ValidationText.Foreground = successBrush;
                break;

            case ValidationState.Invalid:
                ValidationIcon.Text = "\uE7BA"; // Warning
                ValidationIcon.Foreground = errorBrush;
                ValidationText.Text = "API key appears too short (minimum 20 characters)";
                ValidationText.Foreground = errorBrush;
                break;
        }
    }

    // -- Action buttons --

    private void OnSaveClick(object sender, RoutedEventArgs e)
    {
        string key = _isRevealed ? ApiKeyTextBox.Text : ApiKeyPasswordBox.Password;

        if (string.IsNullOrWhiteSpace(key)) return;

        FalAIService.Instance.SaveAPIKey(key.Trim());
        DialogResult = true;
        Close();
    }

    private void OnRemoveClick(object sender, RoutedEventArgs e)
    {
        var result = MessageBox.Show(
            "Are you sure you want to remove the stored API key?",
            "Remove API Key",
            MessageBoxButton.YesNo,
            MessageBoxImage.Question);

        if (result == MessageBoxResult.Yes)
        {
            FalAIService.Instance.RemoveAPIKey();
            ApiKeyPasswordBox.Password = string.Empty;
            ApiKeyTextBox.Text = string.Empty;
            RemoveButton.IsEnabled = false;
            SetValidation(ValidationState.Empty);
        }
    }

    private void OnCancelClick(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }

    // -- External link --

    private void OnFalAiLinkClick(object sender, System.Windows.Input.MouseButtonEventArgs e)
    {
        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = "https://fal.ai/dashboard/keys",
                UseShellExecute = true
            });
        }
        catch
        {
            // Silently fail if browser cannot be opened
        }
    }
}
