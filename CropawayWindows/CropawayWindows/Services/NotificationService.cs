using System.IO;
using System.Media;

namespace CropawayWindows.Services;

/// <summary>
/// Shows Windows tray balloon notifications and plays completion sounds.
/// Uses System.Windows.Forms.NotifyIcon (available because UseWindowsForms=true in csproj).
/// </summary>
public sealed class NotificationService : IDisposable
{
    private static readonly Lazy<NotificationService> _instance = new(() => new NotificationService());
    public static NotificationService Instance => _instance.Value;

    private System.Windows.Forms.NotifyIcon? _notifyIcon;
    private readonly object _lock = new();
    private bool _disposed;

    private NotificationService()
    {
    }

    /// <summary>
    /// Shows a balloon notification that the export completed and plays a system sound.
    /// Safe to call from any thread (marshals to UI thread internally).
    /// </summary>
    public void ShowExportCompleteNotification(string videoName, string outputPath)
    {
        if (_disposed) return;

        // Play the completion sound (works from any thread)
        try
        {
            SystemSounds.Asterisk.Play();
        }
        catch
        {
            // Sound playback is best-effort
        }

        // NotifyIcon must be created/used on a thread with a message pump.
        // WPF's Dispatcher qualifies.
        System.Windows.Application.Current?.Dispatcher.Invoke(() =>
        {
            try
            {
                EnsureNotifyIcon();

                var fileName = Path.GetFileName(outputPath);
                _notifyIcon!.BalloonTipTitle = "Export Complete";
                _notifyIcon.BalloonTipText = $"{videoName} has been exported successfully.\n{fileName}";
                _notifyIcon.BalloonTipIcon = System.Windows.Forms.ToolTipIcon.Info;
                _notifyIcon.Visible = true;
                _notifyIcon.ShowBalloonTip(5000);

                // Hide the tray icon after the balloon auto-dismisses.
                // Windows typically keeps balloon tips visible for ~5-10 seconds;
                // we hide the icon after 12 seconds to avoid a lingering tray entry.
                Task.Delay(TimeSpan.FromSeconds(12)).ContinueWith(_ =>
                {
                    System.Windows.Application.Current?.Dispatcher.Invoke(() =>
                    {
                        if (_notifyIcon != null)
                            _notifyIcon.Visible = false;
                    });
                });
            }
            catch
            {
                // Notification display is best-effort; never crash the app for this
            }
        });
    }

    /// <summary>
    /// Creates the NotifyIcon if it doesn't exist yet.
    /// Must be called on the dispatcher thread.
    /// </summary>
    private void EnsureNotifyIcon()
    {
        lock (_lock)
        {
            if (_notifyIcon != null) return;

            _notifyIcon = new System.Windows.Forms.NotifyIcon
            {
                Text = "Cropaway"
            };

            // Try to load the app icon from the embedded resource
            try
            {
                var iconUri = new Uri("pack://application:,,,/Resources/cropaway.ico", UriKind.Absolute);
                var streamInfo = System.Windows.Application.GetResourceStream(iconUri);
                if (streamInfo != null)
                {
                    _notifyIcon.Icon = new System.Drawing.Icon(streamInfo.Stream);
                }
                else
                {
                    // Fall back to the default application icon
                    _notifyIcon.Icon = System.Drawing.SystemIcons.Application;
                }
            }
            catch
            {
                _notifyIcon.Icon = System.Drawing.SystemIcons.Application;
            }
        }
    }

    /// <summary>
    /// Clean up the NotifyIcon so the tray entry is removed on app exit.
    /// Call this from App.OnExit or equivalent shutdown path.
    /// </summary>
    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;

        lock (_lock)
        {
            if (_notifyIcon != null)
            {
                _notifyIcon.Visible = false;
                _notifyIcon.Dispose();
                _notifyIcon = null;
            }
        }
    }
}
