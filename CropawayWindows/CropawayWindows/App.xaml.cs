using System.Windows;

namespace CropawayWindows;

public partial class App : Application
{
    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // Set up global exception handling
        DispatcherUnhandledException += (s, args) =>
        {
            MessageBox.Show(
                $"An unexpected error occurred:\n\n{args.Exception.Message}",
                "Cropaway - Error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
            args.Handled = true;
        };

        // Initialize services
        Services.CropDataStorageService.Instance.EnsureStorageDirectory();
    }
}
