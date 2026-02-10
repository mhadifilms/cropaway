using System.IO;
using System.Windows;

namespace CropawayWindows;

public partial class App : Application
{
    private static readonly string CrashLogPath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "Cropaway", "crash.log");

    private static void LogCrash(string context, Exception ex)
    {
        try
        {
            var dir = Path.GetDirectoryName(CrashLogPath)!;
            if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
            var msg = $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}] {context}\n{ex}\n\n";
            File.AppendAllText(CrashLogPath, msg);
        }
        catch { /* best effort */ }
    }

    protected override void OnStartup(StartupEventArgs e)
    {
        // Catch absolutely everything and log to file
        AppDomain.CurrentDomain.UnhandledException += (s, args) =>
        {
            var ex = args.ExceptionObject as Exception;
            LogCrash("AppDomain.UnhandledException", ex ?? new Exception(args.ExceptionObject?.ToString()));
        };

        base.OnStartup(e);

        // Set up global exception handling
        DispatcherUnhandledException += (s, args) =>
        {
            LogCrash("DispatcherUnhandledException", args.Exception);
            MessageBox.Show(
                $"An unexpected error occurred:\n\n{args.Exception.Message}\n\nFull details logged to:\n{CrashLogPath}",
                "Cropaway - Error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
            args.Handled = true;
        };

        // Initialize services
        Services.CropDataStorageService.Instance.EnsureStorageDirectory();
    }
}
