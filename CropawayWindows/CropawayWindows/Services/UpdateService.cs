// UpdateService.cs
// CropawayWindows

using System.Diagnostics;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace CropawayWindows.Services;

/// <summary>
/// Represents a GitHub release.
/// </summary>
public class GitHubRelease
{
    [JsonPropertyName("tag_name")]
    public string TagName { get; set; } = "";

    [JsonPropertyName("name")]
    public string Name { get; set; } = "";

    [JsonPropertyName("body")]
    public string? Body { get; set; }

    [JsonPropertyName("html_url")]
    public string HtmlUrl { get; set; } = "";

    [JsonPropertyName("published_at")]
    public string? PublishedAt { get; set; }

    [JsonPropertyName("assets")]
    public List<GitHubAsset> Assets { get; set; } = new();
}

/// <summary>
/// Represents a downloadable asset in a GitHub release.
/// </summary>
public class GitHubAsset
{
    [JsonPropertyName("name")]
    public string Name { get; set; } = "";

    [JsonPropertyName("size")]
    public long Size { get; set; }

    [JsonPropertyName("browser_download_url")]
    public string BrowserDownloadUrl { get; set; } = "";
}

/// <summary>
/// Status of the update check process.
/// </summary>
public enum UpdateStatus
{
    Idle,
    Checking,
    Available,
    UpToDate,
    Downloading,
    ReadyToInstall,
    Error
}

/// <summary>
/// Errors that can occur during update operations.
/// </summary>
public enum UpdateError
{
    NetworkError,
    InvalidResponse,
    NoAssetFound,
    DownloadFailed,
    InstallFailed,
    VersionParseError
}

/// <summary>
/// Exception thrown by the update service.
/// </summary>
public class UpdateException : Exception
{
    public UpdateError ErrorType { get; }

    public UpdateException(UpdateError errorType, string? message = null)
        : base(message ?? errorType.ToString())
    {
        ErrorType = errorType;
    }
}

/// <summary>
/// Information about an available update.
/// </summary>
public class UpdateInfo
{
    public string Version { get; set; } = "";
    public string? ReleaseNotes { get; set; }
    public string? DownloadUrl { get; set; }
    public long DownloadSize { get; set; }
    public string? ReleasePageUrl { get; set; }
}

/// <summary>
/// Simple auto-update service that checks GitHub releases for new versions.
/// Compares semantic versions and provides download functionality.
/// </summary>
public sealed class UpdateService : IDisposable
{
    private static readonly Lazy<UpdateService> _instance =
        new(() => new UpdateService());

    public static UpdateService Instance => _instance.Value;

    // GitHub repository info
    private const string Owner = "mhadifilms";
    private const string Repo = "cropaway";
    private const string ReleasesApiUrl =
        $"https://api.github.com/repos/{Owner}/{Repo}/releases/latest";

    // Registry keys for update preferences
    private const string RegistryPath = @"SOFTWARE\Cropaway";
    private const string LastCheckKey = "UpdateLastCheckDate";
    private const string SkipVersionKey = "UpdateSkipVersion";

    private readonly HttpClient _httpClient;

    /// <summary>Current update status.</summary>
    public UpdateStatus Status { get; private set; } = UpdateStatus.Idle;

    /// <summary>Download progress (0.0 to 1.0).</summary>
    public double DownloadProgress { get; private set; }

    /// <summary>Latest release info (populated after a successful check).</summary>
    public GitHubRelease? LatestRelease { get; private set; }

    /// <summary>Information about the available update, if any.</summary>
    public UpdateInfo? AvailableUpdate { get; private set; }

    /// <summary>Path to the downloaded installer, if ready.</summary>
    public string? DownloadedInstallerPath { get; private set; }

    /// <summary>Last error message.</summary>
    public string? LastError { get; private set; }

    /// <summary>Event raised when status changes.</summary>
    public event Action<UpdateStatus>? StatusChanged;

    private UpdateService()
    {
        _httpClient = new HttpClient();
        _httpClient.DefaultRequestHeaders.Accept.Add(
            new MediaTypeWithQualityHeaderValue("application/vnd.github+json"));
        _httpClient.DefaultRequestHeaders.UserAgent.Add(
            new ProductInfoHeaderValue("Cropaway", CurrentVersion));
        _httpClient.Timeout = TimeSpan.FromSeconds(30);
    }

    #region Version Info

    /// <summary>
    /// Current application version from assembly info.
    /// </summary>
    public string CurrentVersion
    {
        get
        {
            var assembly = Assembly.GetEntryAssembly() ?? Assembly.GetExecutingAssembly();
            var version = assembly.GetName().Version;
            return version != null
                ? $"{version.Major}.{version.Minor}.{version.Build}"
                : "1.0.0";
        }
    }

    /// <summary>
    /// Whether enough time has passed since the last check (24 hours).
    /// </summary>
    public bool ShouldCheckAutomatically
    {
        get
        {
            try
            {
                using var regKey = Microsoft.Win32.Registry.CurrentUser
                    .OpenSubKey(RegistryPath);
                string? lastCheckStr = regKey?.GetValue(LastCheckKey) as string;

                if (lastCheckStr == null || !DateTime.TryParse(lastCheckStr, out DateTime lastCheck))
                    return true;

                return (DateTime.UtcNow - lastCheck).TotalHours >= 24;
            }
            catch
            {
                return true;
            }
        }
    }

    /// <summary>
    /// Version the user chose to skip.
    /// </summary>
    public string? SkippedVersion
    {
        get
        {
            try
            {
                using var regKey = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(RegistryPath);
                return regKey?.GetValue(SkipVersionKey) as string;
            }
            catch { return null; }
        }
        set
        {
            try
            {
                using var regKey = Microsoft.Win32.Registry.CurrentUser
                    .CreateSubKey(RegistryPath);
                if (value != null)
                    regKey?.SetValue(SkipVersionKey, value);
                else
                    regKey?.DeleteValue(SkipVersionKey, throwOnMissingValue: false);
            }
            catch { /* Best effort */ }
        }
    }

    #endregion

    #region Check for Updates

    /// <summary>
    /// Checks GitHub releases for a newer version.
    /// </summary>
    /// <param name="force">If true, ignores the skipped version and time throttle.</param>
    /// <returns>UpdateInfo if an update is available, null if up to date.</returns>
    public async Task<UpdateInfo?> CheckForUpdatesAsync(bool force = false)
    {
        if (Status == UpdateStatus.Checking)
            return null;

        SetStatus(UpdateStatus.Checking);
        LastError = null;

        try
        {
            var release = await FetchLatestReleaseAsync();
            LatestRelease = release;

            // Save check time
            SaveLastCheckTime();

            // Parse version
            string latestVersion = release.TagName.TrimStart('v');

            if (IsVersionNewer(latestVersion, CurrentVersion))
            {
                // Check if user skipped this version
                if (!force && SkippedVersion == latestVersion)
                {
                    SetStatus(UpdateStatus.UpToDate);
                    return null;
                }

                // Find downloadable asset (MSI or EXE installer)
                string? downloadUrl = null;
                long downloadSize = 0;

                var installerAsset = release.Assets.FirstOrDefault(a =>
                    a.Name.EndsWith(".msi", StringComparison.OrdinalIgnoreCase) ||
                    a.Name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) ||
                    a.Name.EndsWith(".msix", StringComparison.OrdinalIgnoreCase));

                if (installerAsset != null)
                {
                    downloadUrl = installerAsset.BrowserDownloadUrl;
                    downloadSize = installerAsset.Size;
                }

                AvailableUpdate = new UpdateInfo
                {
                    Version = latestVersion,
                    ReleaseNotes = release.Body,
                    DownloadUrl = downloadUrl,
                    DownloadSize = downloadSize,
                    ReleasePageUrl = release.HtmlUrl
                };

                SetStatus(UpdateStatus.Available);
                return AvailableUpdate;
            }
            else
            {
                SetStatus(UpdateStatus.UpToDate);
                return null;
            }
        }
        catch (Exception ex)
        {
            LastError = ex.Message;
            SetStatus(UpdateStatus.Error);
            Debug.WriteLine($"[Update] Check failed: {ex.Message}");
            return null;
        }
    }

    /// <summary>
    /// Fetches the latest release from GitHub API.
    /// </summary>
    private async Task<GitHubRelease> FetchLatestReleaseAsync()
    {
        var response = await _httpClient.GetAsync(ReleasesApiUrl);

        if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
            throw new UpdateException(UpdateError.NetworkError, "No releases found.");

        if (!response.IsSuccessStatusCode)
            throw new UpdateException(UpdateError.NetworkError,
                $"HTTP {(int)response.StatusCode}");

        string json = await response.Content.ReadAsStringAsync();
        var release = JsonSerializer.Deserialize<GitHubRelease>(json);

        if (release == null)
            throw new UpdateException(UpdateError.InvalidResponse);

        return release;
    }

    #endregion

    #region Download Update

    /// <summary>
    /// Downloads the update installer to a temporary location.
    /// </summary>
    public async Task<string> DownloadUpdateAsync(CancellationToken cancellationToken = default)
    {
        if (AvailableUpdate?.DownloadUrl == null)
            throw new UpdateException(UpdateError.NoAssetFound,
                "No download URL available. Visit the release page to download manually.");

        SetStatus(UpdateStatus.Downloading);
        DownloadProgress = 0;

        try
        {
            var response = await _httpClient.GetAsync(
                AvailableUpdate.DownloadUrl,
                HttpCompletionOption.ResponseHeadersRead,
                cancellationToken);

            if (!response.IsSuccessStatusCode)
                throw new UpdateException(UpdateError.DownloadFailed,
                    $"HTTP {(int)response.StatusCode}");

            long totalBytes = response.Content.Headers.ContentLength ?? AvailableUpdate.DownloadSize;

            // Determine file name from URL
            string fileName = Path.GetFileName(new Uri(AvailableUpdate.DownloadUrl).LocalPath);
            if (string.IsNullOrEmpty(fileName))
                fileName = $"CropawayUpdate_{AvailableUpdate.Version}.exe";

            string tempPath = Path.Combine(Path.GetTempPath(), fileName);

            // Remove existing file
            if (File.Exists(tempPath))
                File.Delete(tempPath);

            // Download with progress tracking
            using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
            using var fileStream = new FileStream(tempPath, FileMode.Create, FileAccess.Write, FileShare.None);

            var buffer = new byte[81920]; // 80KB buffer
            long bytesRead = 0;
            int count;

            while ((count = await stream.ReadAsync(buffer, cancellationToken)) > 0)
            {
                await fileStream.WriteAsync(buffer.AsMemory(0, count), cancellationToken);
                bytesRead += count;

                if (totalBytes > 0)
                {
                    DownloadProgress = (double)bytesRead / totalBytes;
                    StatusChanged?.Invoke(UpdateStatus.Downloading);
                }
            }

            DownloadedInstallerPath = tempPath;
            SetStatus(UpdateStatus.ReadyToInstall);
            return tempPath;
        }
        catch (OperationCanceledException)
        {
            SetStatus(UpdateStatus.Idle);
            throw new UpdateException(UpdateError.DownloadFailed, "Download cancelled.");
        }
        catch (UpdateException)
        {
            SetStatus(UpdateStatus.Error);
            throw;
        }
        catch (Exception ex)
        {
            LastError = ex.Message;
            SetStatus(UpdateStatus.Error);
            throw new UpdateException(UpdateError.DownloadFailed, ex.Message);
        }
    }

    /// <summary>
    /// Launches the downloaded installer and optionally closes the application.
    /// </summary>
    public void LaunchInstaller()
    {
        if (string.IsNullOrEmpty(DownloadedInstallerPath) || !File.Exists(DownloadedInstallerPath))
            throw new UpdateException(UpdateError.InstallFailed, "No downloaded installer found.");

        try
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = DownloadedInstallerPath,
                UseShellExecute = true
            });
        }
        catch (Exception ex)
        {
            throw new UpdateException(UpdateError.InstallFailed,
                $"Failed to launch installer: {ex.Message}");
        }
    }

    #endregion

    #region User Actions

    /// <summary>
    /// Marks the current available version to be skipped.
    /// </summary>
    public void SkipVersion()
    {
        if (AvailableUpdate != null)
        {
            SkippedVersion = AvailableUpdate.Version;
            SetStatus(UpdateStatus.Idle);
        }
    }

    /// <summary>
    /// Opens the release page in the default browser.
    /// </summary>
    public void OpenReleasePage()
    {
        string? url = AvailableUpdate?.ReleasePageUrl ?? LatestRelease?.HtmlUrl;
        if (!string.IsNullOrEmpty(url))
        {
            Process.Start(new ProcessStartInfo
            {
                FileName = url,
                UseShellExecute = true
            });
        }
    }

    /// <summary>
    /// Resets the service to idle state.
    /// </summary>
    public void Reset()
    {
        SetStatus(UpdateStatus.Idle);
        DownloadProgress = 0;
        AvailableUpdate = null;
        LastError = null;
    }

    #endregion

    #region Version Comparison

    /// <summary>
    /// Compares two semantic version strings (e.g., "1.2.3").
    /// Returns true if v1 is newer than v2.
    /// </summary>
    public static bool IsVersionNewer(string v1, string v2)
    {
        var parts1 = ParseVersionParts(v1);
        var parts2 = ParseVersionParts(v2);

        int maxLen = Math.Max(parts1.Length, parts2.Length);

        for (int i = 0; i < maxLen; i++)
        {
            int p1 = i < parts1.Length ? parts1[i] : 0;
            int p2 = i < parts2.Length ? parts2[i] : 0;

            if (p1 > p2) return true;
            if (p1 < p2) return false;
        }

        return false; // Equal
    }

    /// <summary>
    /// Parses a version string into integer components.
    /// Handles formats like "1.2.3", "v1.2.3", "1.2.3-beta".
    /// </summary>
    private static int[] ParseVersionParts(string version)
    {
        // Strip leading 'v' and any prerelease suffix
        string clean = version.TrimStart('v');
        int dashIndex = clean.IndexOf('-');
        if (dashIndex >= 0)
            clean = clean[..dashIndex];

        return clean.Split('.')
            .Select(s => int.TryParse(s, out int v) ? v : 0)
            .ToArray();
    }

    #endregion

    #region Helpers

    private void SetStatus(UpdateStatus status)
    {
        Status = status;
        StatusChanged?.Invoke(status);
    }

    private void SaveLastCheckTime()
    {
        try
        {
            using var regKey = Microsoft.Win32.Registry.CurrentUser.CreateSubKey(RegistryPath);
            regKey?.SetValue(LastCheckKey, DateTime.UtcNow.ToString("O"));
        }
        catch { /* Best effort */ }
    }

    public void Dispose()
    {
        _httpClient.Dispose();
    }

    #endregion
}
