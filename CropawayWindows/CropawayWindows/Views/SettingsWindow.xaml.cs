using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Media;
using CropawayWindows.Services;
using Microsoft.Win32;

namespace CropawayWindows.Views;

/// <summary>
/// Settings/preferences window for Cropaway.
/// Stores settings in the Windows Registry under HKCU\Software\Cropaway.
/// </summary>
public partial class SettingsWindow : Window
{
    private const string RegistryKeyPath = @"Software\Cropaway";

    private bool _isApiKeyRevealed;
    private string _currentApiKey = string.Empty;

    public SettingsWindow()
    {
        InitializeComponent();
        Loaded += OnLoaded;
    }

    private void OnLoaded(object sender, RoutedEventArgs e)
    {
        LoadSettings();
        UpdateFFmpegStatus();
    }

    // MARK: - Settings Persistence

    private void LoadSettings()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RegistryKeyPath);
        if (key != null)
        {
            FFmpegPathTextBox.Text = key.GetValue("FFmpegPath", "")?.ToString() ?? "";
            _currentApiKey = key.GetValue("FalAIApiKey", "")?.ToString() ?? "";

            string format = key.GetValue("DefaultFormat", "MOV")?.ToString() ?? "MOV";
            SelectComboBoxItem(FormatComboBox, format);

            string codec = key.GetValue("DefaultCodec", "Auto (match source)")?.ToString() ?? "Auto (match source)";
            SelectComboBoxItem(CodecComboBox, codec);

            string theme = key.GetValue("Theme", "Dark")?.ToString() ?? "Dark";
            SelectComboBoxItem(ThemeComboBox, theme);
        }
        else
        {
            // First run: try auto-detecting FFmpeg
            string? detected = FFmpegExportService.FindFFmpeg();
            if (detected != null)
            {
                FFmpegPathTextBox.Text = detected;
            }
        }

        // Set password box content
        if (!string.IsNullOrEmpty(_currentApiKey))
        {
            ApiKeyPasswordBox.Password = _currentApiKey;
        }
    }

    private void SaveSettings()
    {
        using var key = Registry.CurrentUser.CreateSubKey(RegistryKeyPath);
        if (key == null) return;

        key.SetValue("FFmpegPath", FFmpegPathTextBox.Text.Trim());
        key.SetValue("FalAIApiKey", _currentApiKey);

        string format = GetSelectedComboBoxText(FormatComboBox) ?? "MOV";
        key.SetValue("DefaultFormat", format);

        string codec = GetSelectedComboBoxText(CodecComboBox) ?? "Auto (match source)";
        key.SetValue("DefaultCodec", codec);

        string theme = GetSelectedComboBoxText(ThemeComboBox) ?? "Dark";
        key.SetValue("Theme", theme);
    }

    // MARK: - FFmpeg

    private void OnBrowseFFmpeg(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog
        {
            Title = "Select FFmpeg executable",
            Filter = "FFmpeg|ffmpeg.exe|All files|*.*",
            CheckFileExists = true
        };

        if (dialog.ShowDialog(this) == true)
        {
            FFmpegPathTextBox.Text = dialog.FileName;
            UpdateFFmpegStatus();
        }
    }

    private void OnAutoDetectFFmpeg(object sender, RoutedEventArgs e)
    {
        string? detected = FFmpegExportService.FindFFmpeg();
        if (detected != null)
        {
            FFmpegPathTextBox.Text = detected;
            UpdateFFmpegStatus();
        }
        else
        {
            FFmpegPathTextBox.Text = "";
            FFmpegStatusIcon.Text = "\uE783"; // Error icon
            FFmpegStatusIcon.Foreground = (Brush)FindResource("ErrorBrush");
            FFmpegStatusText.Text = "FFmpeg not found. Please install it or browse to the executable.";
            FFmpegStatusText.Foreground = (Brush)FindResource("ErrorBrush");
        }
    }

    private void UpdateFFmpegStatus()
    {
        string path = FFmpegPathTextBox.Text.Trim();

        if (string.IsNullOrEmpty(path))
        {
            // Try auto-detect silently
            string? detected = FFmpegExportService.FindFFmpeg();
            if (detected != null)
            {
                FFmpegStatusIcon.Text = "\uE73E"; // Check icon
                FFmpegStatusIcon.Foreground = (Brush)FindResource("ExportProgressBrush");
                FFmpegStatusText.Text = $"Auto-detected: {detected}";
                FFmpegStatusText.Foreground = (Brush)FindResource("TextSecondaryBrush");
            }
            else
            {
                FFmpegStatusIcon.Text = "\uE7BA"; // Warning icon
                FFmpegStatusIcon.Foreground = (Brush)FindResource("ErrorBrush");
                FFmpegStatusText.Text = "FFmpeg not found. Video export will not work.";
                FFmpegStatusText.Foreground = (Brush)FindResource("ErrorBrush");
            }
        }
        else if (File.Exists(path))
        {
            // Try to get the version
            string version = GetFFmpegVersion(path);
            FFmpegStatusIcon.Text = "\uE73E"; // Check icon
            FFmpegStatusIcon.Foreground = (Brush)FindResource("ExportProgressBrush");
            FFmpegStatusText.Text = string.IsNullOrEmpty(version)
                ? $"Found: {path}"
                : $"Found: {version}";
            FFmpegStatusText.Foreground = (Brush)FindResource("TextSecondaryBrush");
        }
        else
        {
            FFmpegStatusIcon.Text = "\uE783"; // Error icon
            FFmpegStatusIcon.Foreground = (Brush)FindResource("ErrorBrush");
            FFmpegStatusText.Text = "Specified path does not exist.";
            FFmpegStatusText.Foreground = (Brush)FindResource("ErrorBrush");
        }
    }

    private static string GetFFmpegVersion(string ffmpegPath)
    {
        try
        {
            using var process = new Process();
            process.StartInfo = new ProcessStartInfo
            {
                FileName = ffmpegPath,
                Arguments = "-version",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            };

            process.Start();
            string output = process.StandardOutput.ReadLine() ?? "";
            process.WaitForExit(3000);

            // First line is typically "ffmpeg version X.X.X ..."
            if (output.StartsWith("ffmpeg version"))
            {
                return output;
            }
            return output;
        }
        catch
        {
            return "";
        }
    }

    // MARK: - API Key

    private void OnApiKeyPasswordChanged(object sender, RoutedEventArgs e)
    {
        if (!_isApiKeyRevealed)
        {
            _currentApiKey = ApiKeyPasswordBox.Password;
        }
    }

    private void OnApiKeyTextChanged(object sender, System.Windows.Controls.TextChangedEventArgs e)
    {
        if (_isApiKeyRevealed)
        {
            _currentApiKey = ApiKeyTextBox.Text;
        }
    }

    private void OnRevealToggle(object sender, RoutedEventArgs e)
    {
        _isApiKeyRevealed = !_isApiKeyRevealed;

        if (_isApiKeyRevealed)
        {
            // Show plain text
            ApiKeyTextBox.Text = _currentApiKey;
            ApiKeyPasswordBox.Visibility = Visibility.Collapsed;
            ApiKeyTextBox.Visibility = Visibility.Visible;
            RevealIcon.Text = "\uED1A"; // Hide icon
        }
        else
        {
            // Show password box
            ApiKeyPasswordBox.Password = _currentApiKey;
            ApiKeyTextBox.Visibility = Visibility.Collapsed;
            ApiKeyPasswordBox.Visibility = Visibility.Visible;
            RevealIcon.Text = "\uE7B3"; // Reveal icon
        }
    }

    // MARK: - Action Buttons

    private void OnSaveClick(object sender, RoutedEventArgs e)
    {
        SaveSettings();
        DialogResult = true;
        Close();
    }

    private void OnCancelClick(object sender, RoutedEventArgs e)
    {
        DialogResult = false;
        Close();
    }

    // MARK: - Helpers

    private static void SelectComboBoxItem(System.Windows.Controls.ComboBox comboBox, string text)
    {
        foreach (System.Windows.Controls.ComboBoxItem item in comboBox.Items)
        {
            if (item.Content?.ToString() == text)
            {
                comboBox.SelectedItem = item;
                return;
            }
        }
    }

    private static string? GetSelectedComboBoxText(System.Windows.Controls.ComboBox comboBox)
    {
        return (comboBox.SelectedItem as System.Windows.Controls.ComboBoxItem)?.Content?.ToString();
    }

    /// <summary>
    /// Reads a setting from the registry. Used by other parts of the app.
    /// </summary>
    public static string? GetSetting(string name)
    {
        using var key = Registry.CurrentUser.OpenSubKey(RegistryKeyPath);
        return key?.GetValue(name)?.ToString();
    }

    /// <summary>
    /// Gets the configured FFmpeg path, falling back to auto-detection.
    /// </summary>
    public static string? GetFFmpegPath()
    {
        string? configured = GetSetting("FFmpegPath");
        if (!string.IsNullOrEmpty(configured) && File.Exists(configured))
            return configured;

        return FFmpegExportService.FindFFmpeg();
    }

    /// <summary>
    /// Gets the configured fal.ai API key.
    /// </summary>
    public static string? GetFalAIApiKey()
    {
        return GetSetting("FalAIApiKey");
    }
}
