// FalAIService.cs
// CropawayWindows

using System.Diagnostics;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Windows;
using CropawayWindows.Models;

namespace CropawayWindows.Services;

/// <summary>
/// Status of fal.ai processing pipeline.
/// </summary>
public enum FalAIStatus
{
    Idle,
    Uploading,
    Processing,
    Downloading,
    Extracting,
    Completed,
    Error
}

/// <summary>
/// Result from fal.ai SAM3 video tracking.
/// Contains RLE masks and bounding boxes for each tracked frame.
/// </summary>
public class TrackingResult
{
    /// <summary>Frame index -> RLE mask data (pixel-perfect segmentation).</summary>
    public Dictionary<int, byte[]> Masks { get; init; } = new();

    /// <summary>Frame index -> bounding box (normalized 0-1, derived from masks).</summary>
    public Dictionary<int, Rect> BoundingBoxes { get; init; } = new();

    /// <summary>Total number of frames in the tracked video.</summary>
    public int FrameCount { get; init; }
}

/// <summary>
/// Errors that can occur during fal.ai operations.
/// </summary>
public enum FalAIError
{
    NoAPIKey,
    UploadFailed,
    JobSubmissionFailed,
    ProcessingFailed,
    DownloadFailed,
    ExtractionFailed,
    InvalidResponse,
    NoBoundingBoxData,
    Timeout,
    Cancelled,
    ProxyCreationFailed
}

/// <summary>
/// Exception thrown by the fal.ai service.
/// </summary>
public class FalAIException : Exception
{
    public FalAIError ErrorType { get; }

    public FalAIException(FalAIError errorType, string? message = null)
        : base(message ?? GetDefaultMessage(errorType))
    {
        ErrorType = errorType;
    }

    private static string GetDefaultMessage(FalAIError errorType) => errorType switch
    {
        FalAIError.NoAPIKey =>
            "No API key configured. Please add your fal.ai API key in settings.",
        FalAIError.UploadFailed => "Failed to upload video to fal.ai.",
        FalAIError.JobSubmissionFailed => "Failed to submit tracking job.",
        FalAIError.ProcessingFailed => "Processing failed on fal.ai servers.",
        FalAIError.DownloadFailed => "Failed to download results.",
        FalAIError.ExtractionFailed => "Failed to extract bounding box data.",
        FalAIError.InvalidResponse => "Invalid response from fal.ai API.",
        FalAIError.NoBoundingBoxData =>
            "No bounding box data returned. The object may not have been detected.",
        FalAIError.Timeout => "Request timed out after 30 minutes.",
        FalAIError.Cancelled => "Operation was cancelled.",
        FalAIError.ProxyCreationFailed => "Failed to create video proxy for upload.",
        _ => "An unknown fal.ai error occurred."
    };
}

/// <summary>
/// Internal response from queue submission.
/// </summary>
internal record QueueSubmissionResponse(string RequestId, string StatusUrl, string ResponseUrl);

/// <summary>
/// Cloud-based AI video tracking service using fal.ai SAM3 API.
/// Supports text prompts and point prompts for object tracking.
/// API key is stored in user settings (Properties.Settings).
/// </summary>
public sealed class FalAIService : IDisposable
{
    private static readonly Lazy<FalAIService> _instance = new(() => new FalAIService());
    public static FalAIService Instance => _instance.Value;

    // API endpoints
    private const string QueueEndpoint = "https://queue.fal.run/fal-ai/sam-3/video-rle";
    private const string TokenEndpoint = "https://rest.alpha.fal.ai/storage/auth/token?storage_type=fal-cdn-v3";
    private const string StatusBaseUrl = "https://queue.fal.run/fal-ai/sam-3/video-rle/requests";

    // Settings key for API key storage
    private const string ApiKeySettingsKey = "FalAIAPIKey";

    // Maximum file size before proxy creation (50 MB)
    private const long MaxDirectUploadSize = 50 * 1024 * 1024;

    // Maximum poll time (30 minutes)
    private static readonly TimeSpan MaxPollDuration = TimeSpan.FromMinutes(30);
    private static readonly TimeSpan PollInterval = TimeSpan.FromSeconds(5);

    private readonly HttpClient _httpClient;
    private CancellationTokenSource? _cancellationTokenSource;

    /// <summary>Current processing status.</summary>
    public FalAIStatus Status { get; private set; } = FalAIStatus.Idle;

    /// <summary>Progress value (0.0 to 1.0) for the current status phase.</summary>
    public double Progress { get; private set; }

    /// <summary>Whether a tracking operation is currently in progress.</summary>
    public bool IsProcessing { get; private set; }

    /// <summary>Last error message, if any.</summary>
    public string? LastError { get; private set; }

    /// <summary>Event raised when status changes.</summary>
    public event Action<FalAIStatus, double>? StatusChanged;

    private FalAIService()
    {
        var handler = new HttpClientHandler();
        _httpClient = new HttpClient(handler)
        {
            Timeout = TimeSpan.FromMinutes(30)
        };
    }

    #region API Key Management

    /// <summary>Whether an API key is configured.</summary>
    public bool HasAPIKey
    {
        get
        {
            string? key = GetAPIKey();
            return !string.IsNullOrWhiteSpace(key);
        }
    }

    /// <summary>Gets the stored API key.</summary>
    public string? GetAPIKey()
    {
        // Use isolated storage or registry for user settings on Windows
        try
        {
            return Microsoft.Win32.Registry.CurrentUser
                .OpenSubKey(@"SOFTWARE\Cropaway")?
                .GetValue(ApiKeySettingsKey) as string;
        }
        catch
        {
            return null;
        }
    }

    /// <summary>Saves the API key to user settings.</summary>
    public void SaveAPIKey(string key)
    {
        try
        {
            using var regKey = Microsoft.Win32.Registry.CurrentUser
                .CreateSubKey(@"SOFTWARE\Cropaway");
            regKey?.SetValue(ApiKeySettingsKey, key);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[FalAI] Failed to save API key: {ex.Message}");
        }
    }

    /// <summary>Removes the stored API key.</summary>
    public void RemoveAPIKey()
    {
        try
        {
            using var regKey = Microsoft.Win32.Registry.CurrentUser
                .OpenSubKey(@"SOFTWARE\Cropaway", writable: true);
            regKey?.DeleteValue(ApiKeySettingsKey, throwOnMissingValue: false);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[FalAI] Failed to remove API key: {ex.Message}");
        }
    }

    /// <summary>Validates that the key looks like a valid fal.ai API key.</summary>
    public static bool IsValidAPIKeyFormat(string key)
    {
        return !string.IsNullOrWhiteSpace(key) && key.Length >= 20;
    }

    #endregion

    #region Video Tracking

    /// <summary>
    /// Tracks an object in a video using text or point prompt.
    /// </summary>
    /// <param name="videoFilePath">Local path to the video file.</param>
    /// <param name="prompt">Text description of object to track (e.g., "person", "car").</param>
    /// <param name="pointPrompt">Click point in normalized 0-1 coordinates for frame 0.</param>
    /// <param name="videoWidth">Width of the video in pixels.</param>
    /// <param name="videoHeight">Height of the video in pixels.</param>
    /// <param name="frameRate">Video frame rate for timestamp calculation.</param>
    /// <returns>Tracking result with masks and bounding boxes.</returns>
    public async Task<TrackingResult> TrackObjectAsync(
        string videoFilePath,
        string? prompt = null,
        Point? pointPrompt = null,
        int videoWidth = 1920,
        int videoHeight = 1080,
        double frameRate = 30.0)
    {
        string? apiKey = GetAPIKey();
        if (string.IsNullOrWhiteSpace(apiKey))
            throw new FalAIException(FalAIError.NoAPIKey);

        _cancellationTokenSource = new CancellationTokenSource();
        var token = _cancellationTokenSource.Token;

        IsProcessing = true;
        LastError = null;
        UpdateStatus(FalAIStatus.Uploading, 0);

        try
        {
            // Step 1: Upload video to fal.ai CDN storage
            string uploadedUrl = await UploadVideoAsync(videoFilePath, apiKey, token);

            // Step 2: Submit tracking job
            UpdateStatus(FalAIStatus.Processing, 0);
            var submission = await SubmitJobAsync(
                uploadedUrl, prompt, pointPrompt,
                videoWidth, videoHeight, apiKey, token);

            // Step 3: Poll for results
            var result = await PollForResultAsync(
                submission, apiKey, videoWidth, videoHeight, token);

            UpdateStatus(FalAIStatus.Completed, 1.0);
            IsProcessing = false;
            return result;
        }
        catch (Exception ex) when (ex is not FalAIException)
        {
            IsProcessing = false;
            string errorMessage = ex.Message;
            LastError = errorMessage;
            UpdateStatus(FalAIStatus.Error, 0);
            throw new FalAIException(FalAIError.ProcessingFailed, errorMessage);
        }
        catch
        {
            IsProcessing = false;
            UpdateStatus(FalAIStatus.Error, 0);
            throw;
        }
    }

    /// <summary>
    /// Cancels the current tracking operation.
    /// </summary>
    public void CancelTracking()
    {
        _cancellationTokenSource?.Cancel();
        IsProcessing = false;
        UpdateStatus(FalAIStatus.Idle, 0);
    }

    #endregion

    #region Upload

    /// <summary>
    /// Uploads a video to fal.ai CDN storage.
    /// Creates an H.264 proxy if the file is over 50MB.
    /// </summary>
    private async Task<string> UploadVideoAsync(
        string videoFilePath, string apiKey, CancellationToken token)
    {
        Debug.WriteLine($"[FalAI] Preparing video: {Path.GetFileName(videoFilePath)}");

        var fileInfo = new FileInfo(videoFilePath);
        if (!fileInfo.Exists)
            throw new FalAIException(FalAIError.UploadFailed, "Video file not found.");

        Debug.WriteLine($"[FalAI] Original size: {fileInfo.Length / (1024.0 * 1024.0):F1} MB");

        string uploadFilePath = videoFilePath;
        string? proxyPath = null;

        // Create proxy if file is too large
        if (fileInfo.Length > MaxDirectUploadSize)
        {
            UpdateStatus(FalAIStatus.Uploading, 0.1);
            proxyPath = await CreateProxyAsync(videoFilePath, token);
            uploadFilePath = proxyPath;
        }

        try
        {
            // Step 1: Get upload token
            UpdateStatus(FalAIStatus.Uploading, 0.2);
            Debug.WriteLine("[FalAI] Getting upload token...");

            var tokenRequest = new HttpRequestMessage(HttpMethod.Post, TokenEndpoint);
            tokenRequest.Headers.Authorization = new AuthenticationHeaderValue("Key", apiKey);
            tokenRequest.Content = new StringContent("{}", Encoding.UTF8, "application/json");

            var tokenResponse = await _httpClient.SendAsync(tokenRequest, token);
            string tokenBody = await tokenResponse.Content.ReadAsStringAsync(token);

            if (!tokenResponse.IsSuccessStatusCode)
            {
                throw new FalAIException(FalAIError.UploadFailed,
                    $"Failed to get upload token: HTTP {(int)tokenResponse.StatusCode}: {tokenBody}");
            }

            var tokenJson = JsonDocument.Parse(tokenBody).RootElement;
            string uploadToken = tokenJson.GetProperty("token").GetString()
                ?? throw new FalAIException(FalAIError.UploadFailed, "No token in response.");
            string tokenType = tokenJson.GetProperty("token_type").GetString() ?? "Bearer";

            // Get base upload URL
            string baseUploadUrl = "https://v3.fal.media";
            if (tokenJson.TryGetProperty("base_url", out var baseUrlProp))
                baseUploadUrl = baseUrlProp.GetString() ?? baseUploadUrl;
            else if (tokenJson.TryGetProperty("base_upload_url", out var baseUploadUrlProp))
                baseUploadUrl = baseUploadUrlProp.GetString() ?? baseUploadUrl;

            Debug.WriteLine($"[FalAI] Got upload token, base URL: {baseUploadUrl}");

            // Step 2: Upload file to CDN
            UpdateStatus(FalAIStatus.Uploading, 0.4);
            byte[] videoData = await File.ReadAllBytesAsync(uploadFilePath, token);
            Debug.WriteLine($"[FalAI] Upload size: {videoData.Length / (1024.0 * 1024.0):F1} MB");

            string cdnUploadUrl = $"{baseUploadUrl}/files/upload";
            var uploadRequest = new HttpRequestMessage(HttpMethod.Post, cdnUploadUrl);
            uploadRequest.Headers.Authorization =
                new AuthenticationHeaderValue(tokenType, uploadToken);
            uploadRequest.Content = new ByteArrayContent(videoData);
            uploadRequest.Content.Headers.ContentType =
                new MediaTypeHeaderValue("video/mp4");
            uploadRequest.Headers.TryAddWithoutValidation("X-Fal-File-Name", "proxy.mp4");

            Debug.WriteLine($"[FalAI] Uploading to: {cdnUploadUrl}");

            var uploadResponse = await _httpClient.SendAsync(uploadRequest, token);
            string uploadBody = await uploadResponse.Content.ReadAsStringAsync(token);

            if (!uploadResponse.IsSuccessStatusCode)
            {
                throw new FalAIException(FalAIError.UploadFailed,
                    $"Upload failed: HTTP {(int)uploadResponse.StatusCode}: {uploadBody}");
            }

            var uploadJson = JsonDocument.Parse(uploadBody).RootElement;

            // Try to get access URL from response
            string? accessUrl = null;
            if (uploadJson.TryGetProperty("access_url", out var accessUrlProp))
                accessUrl = accessUrlProp.GetString();
            else if (uploadJson.TryGetProperty("url", out var urlProp))
                accessUrl = urlProp.GetString();

            if (string.IsNullOrEmpty(accessUrl))
            {
                throw new FalAIException(FalAIError.UploadFailed,
                    $"Could not parse upload response: {uploadBody}");
            }

            Debug.WriteLine($"[FalAI] Video uploaded: {accessUrl}");
            UpdateStatus(FalAIStatus.Uploading, 1.0);
            return accessUrl;
        }
        finally
        {
            // Clean up proxy file
            if (proxyPath != null)
            {
                try { File.Delete(proxyPath); }
                catch { /* Best effort */ }
            }
        }
    }

    /// <summary>
    /// Creates a lightweight H.264 proxy video for upload.
    /// </summary>
    private async Task<string> CreateProxyAsync(string sourceFilePath, CancellationToken token)
    {
        Debug.WriteLine($"[FalAI] Creating proxy for: {Path.GetFileName(sourceFilePath)}");

        string? ffmpegPath = FFmpegExportService.FindFFmpeg();
        if (ffmpegPath == null)
        {
            throw new FalAIException(FalAIError.ProxyCreationFailed,
                "FFmpeg not found. Cannot create video proxy for upload.");
        }

        string proxyPath = Path.Combine(Path.GetTempPath(), $"proxy_{Guid.NewGuid()}.mp4");

        using var process = new Process();
        process.StartInfo = new ProcessStartInfo
        {
            FileName = ffmpegPath,
            Arguments = $"-i \"{sourceFilePath}\" " +
                        "-c:v libx264 -preset veryfast -crf 28 " +
                        "-c:a aac -b:a 128k " +
                        "-movflags +faststart " +
                        $"-y \"{proxyPath}\"",
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        process.Start();

        // Read stderr to prevent deadlock
        _ = process.StandardError.ReadToEndAsync();

        await process.WaitForExitAsync(token);

        if (process.ExitCode != 0 || !File.Exists(proxyPath))
        {
            throw new FalAIException(FalAIError.ProxyCreationFailed,
                $"Proxy creation failed with exit code {process.ExitCode}.");
        }

        var proxyInfo = new FileInfo(proxyPath);
        Debug.WriteLine($"[FalAI] Proxy created: {proxyInfo.Length / (1024.0 * 1024.0):F1} MB");

        return proxyPath;
    }

    #endregion

    #region Job Submission

    /// <summary>
    /// Submits a tracking job to the fal.ai queue.
    /// </summary>
    private async Task<QueueSubmissionResponse> SubmitJobAsync(
        string videoUrl, string? prompt, Point? pointPrompt,
        int videoWidth, int videoHeight, string apiKey, CancellationToken token)
    {
        Debug.WriteLine("[FalAI] Submitting tracking job");

        var body = new JsonObject
        {
            ["video_url"] = videoUrl
        };

        // Add text prompt if provided
        if (!string.IsNullOrWhiteSpace(prompt))
        {
            body["prompt"] = prompt;
        }

        // Add point prompt if provided (normalized -> pixel coordinates)
        if (pointPrompt.HasValue)
        {
            int pixelX = (int)(pointPrompt.Value.X * videoWidth);
            int pixelY = (int)(pointPrompt.Value.Y * videoHeight);

            var pointPromptObj = new JsonObject
            {
                ["x"] = pixelX,
                ["y"] = pixelY,
                ["label"] = 1,        // 1 = foreground
                ["frame_index"] = 0,
                ["object_id"] = 1
            };

            body["point_prompts"] = new JsonArray { pointPromptObj };

            Debug.WriteLine($"[FalAI] Point prompt: pixel=({pixelX}, {pixelY}) " +
                            $"normalized=({pointPrompt.Value.X:F3}, {pointPrompt.Value.Y:F3}) " +
                            $"videoSize={videoWidth}x{videoHeight}");
        }

        var request = new HttpRequestMessage(HttpMethod.Post, QueueEndpoint);
        request.Headers.Authorization = new AuthenticationHeaderValue("Key", apiKey);
        request.Content = new StringContent(
            body.ToJsonString(), Encoding.UTF8, "application/json");

        Debug.WriteLine($"[FalAI] Request body: {body.ToJsonString()}");

        var response = await _httpClient.SendAsync(request, token);
        string responseBody = await response.Content.ReadAsStringAsync(token);

        Debug.WriteLine($"[FalAI] Submit response: {responseBody}");

        if (!response.IsSuccessStatusCode)
        {
            throw new FalAIException(FalAIError.JobSubmissionFailed,
                $"HTTP {(int)response.StatusCode}: {responseBody}");
        }

        var json = JsonDocument.Parse(responseBody).RootElement;

        if (!json.TryGetProperty("request_id", out var requestIdProp))
        {
            throw new FalAIException(FalAIError.JobSubmissionFailed,
                $"Could not parse response: {responseBody}");
        }

        string requestId = requestIdProp.GetString()!;

        // Get the status and response URLs
        string statusUrl = json.TryGetProperty("status_url", out var statusUrlProp)
            ? statusUrlProp.GetString() ?? $"{StatusBaseUrl}/{requestId}/status"
            : $"{StatusBaseUrl}/{requestId}/status";

        string responseUrl = json.TryGetProperty("response_url", out var responseUrlProp)
            ? responseUrlProp.GetString() ?? $"{StatusBaseUrl}/{requestId}"
            : $"{StatusBaseUrl}/{requestId}";

        Debug.WriteLine($"[FalAI] Job submitted: {requestId}");
        Debug.WriteLine($"[FalAI] Status URL: {statusUrl}");
        Debug.WriteLine($"[FalAI] Response URL: {responseUrl}");

        return new QueueSubmissionResponse(requestId, statusUrl, responseUrl);
    }

    #endregion

    #region Polling & Result Parsing

    /// <summary>
    /// Polls the fal.ai queue for job completion, then fetches and parses results.
    /// </summary>
    private async Task<TrackingResult> PollForResultAsync(
        QueueSubmissionResponse submission, string apiKey,
        int videoWidth, int videoHeight, CancellationToken token)
    {
        Debug.WriteLine($"[FalAI] Polling for results: {submission.RequestId}");

        var deadline = DateTime.UtcNow + MaxPollDuration;
        int pollCount = 0;

        while (DateTime.UtcNow < deadline)
        {
            token.ThrowIfCancellationRequested();

            try
            {
                var request = new HttpRequestMessage(HttpMethod.Get, submission.StatusUrl);
                request.Headers.Authorization = new AuthenticationHeaderValue("Key", apiKey);
                request.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

                var response = await _httpClient.SendAsync(request, token);
                string body = await response.Content.ReadAsStringAsync(token);

                Debug.WriteLine($"[FalAI] Poll #{pollCount} HTTP {(int)response.StatusCode}");

                if (!response.IsSuccessStatusCode)
                {
                    if ((int)response.StatusCode >= 500)
                    {
                        // Server error - retry
                        await Task.Delay(PollInterval, token);
                        pollCount++;
                        continue;
                    }
                }

                var json = JsonDocument.Parse(body).RootElement;

                // Check for status field
                if (!json.TryGetProperty("status", out var statusProp))
                {
                    // Response might be the result itself
                    if (json.TryGetProperty("rle", out _) || json.TryGetProperty("boxes", out _))
                    {
                        Debug.WriteLine("[FalAI] Found result data in poll response, parsing...");
                        return ParseResult(body, videoWidth, videoHeight);
                    }

                    await Task.Delay(PollInterval, token);
                    pollCount++;
                    continue;
                }

                string status = statusProp.GetString() ?? "";
                Debug.WriteLine($"[FalAI] Status: {status}");

                switch (status)
                {
                    case "COMPLETED":
                    {
                        // Fetch the full result
                        var resultRequest = new HttpRequestMessage(HttpMethod.Get, submission.ResponseUrl);
                        resultRequest.Headers.Authorization = new AuthenticationHeaderValue("Key", apiKey);
                        resultRequest.Headers.Accept.Add(new MediaTypeWithQualityHeaderValue("application/json"));

                        Debug.WriteLine($"[FalAI] Fetching result from: {submission.ResponseUrl}");
                        var resultResponse = await _httpClient.SendAsync(resultRequest, token);
                        string resultBody = await resultResponse.Content.ReadAsStringAsync(token);

                        return ParseResult(resultBody, videoWidth, videoHeight);
                    }

                    case "FAILED":
                    {
                        string errorMsg = json.TryGetProperty("error", out var errorProp)
                            ? errorProp.GetString() ?? "Processing failed"
                            : "Processing failed";
                        throw new FalAIException(FalAIError.ProcessingFailed, errorMsg);
                    }

                    case "IN_PROGRESS":
                    case "IN_QUEUE":
                    case "PENDING":
                    {
                        // Update progress if log data available
                        if (json.TryGetProperty("logs", out var logs) &&
                            logs.ValueKind == JsonValueKind.Array && logs.GetArrayLength() > 0)
                        {
                            var lastLog = logs[logs.GetArrayLength() - 1];
                            if (lastLog.TryGetProperty("message", out var msgProp))
                                Debug.WriteLine($"[FalAI] Log: {msgProp.GetString()}");
                        }
                        break;
                    }

                    default:
                        Debug.WriteLine($"[FalAI] Unknown status: {status}");
                        break;
                }
            }
            catch (HttpRequestException ex)
            {
                Debug.WriteLine($"[FalAI] Network error during poll: {ex.Message}");
                // Retry on network errors
            }
            catch (FalAIException)
            {
                throw;
            }

            await Task.Delay(PollInterval, token);
            pollCount++;
        }

        throw new FalAIException(FalAIError.Timeout);
    }

    /// <summary>
    /// Parses the JSON result from the fal.ai video-rle endpoint.
    /// Response format: { rle: [...], boxes: [[cx, cy, w, h], ...] }
    /// </summary>
    private static TrackingResult ParseResult(
        string jsonString, int videoWidth, int videoHeight)
    {
        Debug.WriteLine("[FalAI] Parsing video-rle result");

        var json = JsonDocument.Parse(jsonString).RootElement;

        // Default size for COCO RLE [height, width]
        int[] defaultSize = { videoHeight, videoWidth };

        var masks = new Dictionary<int, byte[]>();
        var boundingBoxes = new Dictionary<int, Rect>();
        int frameCount = 0;

        // Extract RLE masks
        if (json.TryGetProperty("rle", out var rleArray) &&
            rleArray.ValueKind == JsonValueKind.Array)
        {
            Debug.WriteLine($"[FalAI] Found rle array with {rleArray.GetArrayLength()} items");
            frameCount = rleArray.GetArrayLength();

            int frameIndex = 0;
            foreach (var rle in rleArray.EnumerateArray())
            {
                byte[]? rleData = ConvertRLEToData(rle, defaultSize);
                if (rleData != null)
                {
                    masks[frameIndex] = rleData;
                }
                frameIndex++;
            }
        }

        // Extract bounding boxes
        if (json.TryGetProperty("boxes", out var boxesArray) &&
            boxesArray.ValueKind == JsonValueKind.Array)
        {
            Debug.WriteLine($"[FalAI] Found boxes array with {boxesArray.GetArrayLength()} items");
            frameCount = Math.Max(frameCount, boxesArray.GetArrayLength());

            int frameIndex = 0;
            foreach (var box in boxesArray.EnumerateArray())
            {
                if (box.ValueKind == JsonValueKind.Array && box.GetArrayLength() >= 4)
                {
                    double cx = box[0].GetDouble();
                    double cy = box[1].GetDouble();
                    double w = box[2].GetDouble();
                    double h = box[3].GetDouble();

                    boundingBoxes[frameIndex] = new Rect(
                        cx - w / 2, cy - h / 2, w, h);
                }
                frameIndex++;
            }
        }

        // Check metadata array for per-frame data
        if (json.TryGetProperty("metadata", out var metadataArray) &&
            metadataArray.ValueKind == JsonValueKind.Array)
        {
            Debug.WriteLine($"[FalAI] Found metadata array with {metadataArray.GetArrayLength()} items");

            int idx = 0;
            foreach (var item in metadataArray.EnumerateArray())
            {
                int index = item.TryGetProperty("index", out var indexProp)
                    ? indexProp.GetInt32()
                    : idx;

                // Extract RLE from metadata
                if (!masks.ContainsKey(index) &&
                    item.TryGetProperty("rle", out var rle))
                {
                    byte[]? rleData = ConvertRLEToData(rle, defaultSize);
                    if (rleData != null)
                        masks[index] = rleData;
                }

                // Extract bounding box from metadata
                if (!boundingBoxes.ContainsKey(index) &&
                    item.TryGetProperty("box", out var box) &&
                    box.ValueKind == JsonValueKind.Array && box.GetArrayLength() >= 4)
                {
                    double cx = box[0].GetDouble();
                    double cy = box[1].GetDouble();
                    double w = box[2].GetDouble();
                    double h = box[3].GetDouble();

                    boundingBoxes[index] = new Rect(cx - w / 2, cy - h / 2, w, h);
                }

                frameCount = Math.Max(frameCount, index + 1);
                idx++;
            }
        }

        Debug.WriteLine($"[FalAI] Parsed {masks.Count} RLE masks and " +
                        $"{boundingBoxes.Count} bounding boxes from {frameCount} frames");

        if (masks.Count == 0)
            throw new FalAIException(FalAIError.NoBoundingBoxData);

        return new TrackingResult
        {
            Masks = masks,
            BoundingBoxes = boundingBoxes,
            FrameCount = frameCount
        };
    }

    /// <summary>
    /// Converts various RLE formats to JSON byte data for storage.
    /// Supports string (fal.ai format), dictionary (COCO), and array formats.
    /// </summary>
    private static byte[]? ConvertRLEToData(JsonElement rle, int[] defaultSize)
    {
        switch (rle.ValueKind)
        {
            case JsonValueKind.String:
            {
                string rleString = rle.GetString()!;
                if (rleString.StartsWith("{"))
                {
                    // JSON string - parse and ensure size field
                    try
                    {
                        var doc = JsonDocument.Parse(rleString);
                        var root = doc.RootElement;
                        if (!root.TryGetProperty("size", out _))
                        {
                            // Add size field
                            var obj = new JsonObject();
                            foreach (var prop in root.EnumerateObject())
                                obj[prop.Name] = JsonNode.Parse(prop.Value.GetRawText());
                            obj["size"] = new JsonArray(defaultSize[0], defaultSize[1]);
                            return Encoding.UTF8.GetBytes(obj.ToJsonString());
                        }
                        return Encoding.UTF8.GetBytes(rleString);
                    }
                    catch
                    {
                        return Encoding.UTF8.GetBytes(rleString);
                    }
                }
                else
                {
                    // Raw counts string - wrap with size
                    var dict = new JsonObject
                    {
                        ["counts"] = rleString,
                        ["size"] = new JsonArray(defaultSize[0], defaultSize[1])
                    };
                    return Encoding.UTF8.GetBytes(dict.ToJsonString());
                }
            }

            case JsonValueKind.Object:
            {
                // Standard COCO RLE dict format
                var obj = new JsonObject();
                foreach (var prop in rle.EnumerateObject())
                    obj[prop.Name] = JsonNode.Parse(prop.Value.GetRawText());

                if (!rle.TryGetProperty("size", out _))
                    obj["size"] = new JsonArray(defaultSize[0], defaultSize[1]);

                return Encoding.UTF8.GetBytes(obj.ToJsonString());
            }

            case JsonValueKind.Array:
            {
                // Array of counts
                var countsArray = new JsonArray();
                foreach (var item in rle.EnumerateArray())
                    countsArray.Add(item.GetInt32());

                var dict = new JsonObject
                {
                    ["counts"] = countsArray,
                    ["size"] = new JsonArray(defaultSize[0], defaultSize[1])
                };
                return Encoding.UTF8.GetBytes(dict.ToJsonString());
            }

            default:
                Debug.WriteLine($"[FalAI] Unknown RLE type: {rle.ValueKind}");
                return null;
        }
    }

    #endregion

    #region Helpers

    private void UpdateStatus(FalAIStatus status, double progress)
    {
        Status = status;
        Progress = progress;
        LastError = status == FalAIStatus.Error ? LastError : null;
        StatusChanged?.Invoke(status, progress);
    }

    public void Dispose()
    {
        _cancellationTokenSource?.Cancel();
        _cancellationTokenSource?.Dispose();
        _httpClient.Dispose();
    }

    #endregion
}
