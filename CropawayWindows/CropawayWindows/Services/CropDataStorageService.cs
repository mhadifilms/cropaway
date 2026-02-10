// CropDataStorageService.cs
// CropawayWindows

using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Windows;
using CropawayWindows.Models;

namespace CropawayWindows.Services;

#region Storage Document Types

/// <summary>
/// Root document for crop data persistence.
/// Contains source video info, crop settings, keyframes, and computed output bounds.
/// </summary>
public class CropStorageDocument
{
    [JsonPropertyName("version")]
    public string Version { get; set; } = "2.0";

    [JsonPropertyName("savedAt")]
    public DateTime SavedAt { get; set; }

    [JsonPropertyName("source")]
    public SourceInfo Source { get; set; } = new();

    [JsonPropertyName("crop")]
    public CropData Crop { get; set; } = new();

    [JsonPropertyName("outputBounds")]
    public OutputBounds OutputBounds { get; set; } = new();
}

/// <summary>Source video metadata snapshot.</summary>
public class SourceInfo
{
    [JsonPropertyName("filePath")]
    public string FilePath { get; set; } = "";

    [JsonPropertyName("fileName")]
    public string FileName { get; set; } = "";

    [JsonPropertyName("width")]
    public int Width { get; set; }

    [JsonPropertyName("height")]
    public int Height { get; set; }

    [JsonPropertyName("duration")]
    public double Duration { get; set; }

    [JsonPropertyName("frameRate")]
    public double FrameRate { get; set; }

    [JsonPropertyName("codec")]
    public string Codec { get; set; } = "";

    [JsonPropertyName("isHDR")]
    public bool IsHDR { get; set; }

    [JsonPropertyName("colorSpace")]
    public string? ColorSpace { get; set; }

    [JsonPropertyName("bitDepth")]
    public int BitDepth { get; set; } = 8;

    [JsonPropertyName("bitRate")]
    public long BitRate { get; set; }
}

/// <summary>Crop configuration data including all modes and keyframes.</summary>
public class CropData
{
    [JsonPropertyName("mode")]
    public string Mode { get; set; } = "rectangle";

    [JsonPropertyName("rectangle")]
    public RectangleData? Rectangle { get; set; }

    [JsonPropertyName("circle")]
    public CircleData? Circle { get; set; }

    [JsonPropertyName("freehand")]
    public FreehandData? Freehand { get; set; }

    [JsonPropertyName("ai")]
    public AIData? AI { get; set; }

    [JsonPropertyName("keyframes")]
    public List<KeyframeStorageData>? Keyframes { get; set; }
}

/// <summary>Rectangle crop data (normalized 0-1).</summary>
public class RectangleData
{
    [JsonPropertyName("x")]
    public double X { get; set; }

    [JsonPropertyName("y")]
    public double Y { get; set; }

    [JsonPropertyName("width")]
    public double Width { get; set; }

    [JsonPropertyName("height")]
    public double Height { get; set; }
}

/// <summary>Circle crop data (normalized 0-1).</summary>
public class CircleData
{
    [JsonPropertyName("centerX")]
    public double CenterX { get; set; }

    [JsonPropertyName("centerY")]
    public double CenterY { get; set; }

    [JsonPropertyName("radius")]
    public double Radius { get; set; }
}

/// <summary>Freehand mask data with bezier vertices.</summary>
public class FreehandData
{
    [JsonPropertyName("vertices")]
    public List<VertexData> Vertices { get; set; } = new();
}

/// <summary>AI tracking data with mask, bounding box, and prompt info.</summary>
public class AIData
{
    [JsonPropertyName("maskDataBase64")]
    public string? MaskDataBase64 { get; set; }

    [JsonPropertyName("boundingBoxX")]
    public double BoundingBoxX { get; set; }

    [JsonPropertyName("boundingBoxY")]
    public double BoundingBoxY { get; set; }

    [JsonPropertyName("boundingBoxWidth")]
    public double BoundingBoxWidth { get; set; }

    [JsonPropertyName("boundingBoxHeight")]
    public double BoundingBoxHeight { get; set; }

    [JsonPropertyName("textPrompt")]
    public string? TextPrompt { get; set; }

    [JsonPropertyName("confidence")]
    public double Confidence { get; set; }

    [JsonPropertyName("promptPoints")]
    public List<AIPromptPointData>? PromptPoints { get; set; }
}

/// <summary>A point prompt for AI segmentation.</summary>
public class AIPromptPointData
{
    [JsonPropertyName("x")]
    public double X { get; set; }

    [JsonPropertyName("y")]
    public double Y { get; set; }

    [JsonPropertyName("isPositive")]
    public bool IsPositive { get; set; }
}

/// <summary>A vertex in the freehand mask path, with optional bezier control handles.</summary>
public class VertexData
{
    [JsonPropertyName("x")]
    public double X { get; set; }

    [JsonPropertyName("y")]
    public double Y { get; set; }

    [JsonPropertyName("controlInX")]
    public double? ControlInX { get; set; }

    [JsonPropertyName("controlInY")]
    public double? ControlInY { get; set; }

    [JsonPropertyName("controlOutX")]
    public double? ControlOutX { get; set; }

    [JsonPropertyName("controlOutY")]
    public double? ControlOutY { get; set; }
}

/// <summary>Keyframe data for animated crops.</summary>
public class KeyframeStorageData
{
    [JsonPropertyName("timestamp")]
    public double Timestamp { get; set; }

    [JsonPropertyName("interpolation")]
    public string Interpolation { get; set; } = "linear";

    [JsonPropertyName("rectangle")]
    public RectangleData? Rectangle { get; set; }

    [JsonPropertyName("circle")]
    public CircleData? Circle { get; set; }

    [JsonPropertyName("freehand")]
    public FreehandData? Freehand { get; set; }

    [JsonPropertyName("ai")]
    public AIData? AI { get; set; }
}

/// <summary>Pre-computed pixel values for easy uncropping.</summary>
public class OutputBounds
{
    [JsonPropertyName("cropPixelX")]
    public int CropPixelX { get; set; }

    [JsonPropertyName("cropPixelY")]
    public int CropPixelY { get; set; }

    [JsonPropertyName("cropPixelWidth")]
    public int CropPixelWidth { get; set; }

    [JsonPropertyName("cropPixelHeight")]
    public int CropPixelHeight { get; set; }

    [JsonPropertyName("originalWidth")]
    public int OriginalWidth { get; set; }

    [JsonPropertyName("originalHeight")]
    public int OriginalHeight { get; set; }

    /// <summary>FFmpeg crop filter string.</summary>
    [JsonIgnore]
    public string FFmpegCropFilter =>
        $"crop={CropPixelWidth}:{CropPixelHeight}:{CropPixelX}:{CropPixelY}";

    /// <summary>FFmpeg pad filter to restore original dimensions.</summary>
    [JsonIgnore]
    public string FFmpegUncropFilter =>
        $"pad={OriginalWidth}:{OriginalHeight}:{CropPixelX}:{CropPixelY}";
}

#endregion

/// <summary>
/// Persistent crop data storage service.
/// Saves crop data to AppData/Local/Cropaway/crop-data/ using SHA256 hash of the file path as key.
/// Thread-safe for concurrent read/write operations.
/// </summary>
public sealed class CropDataStorageService
{
    private static readonly Lazy<CropDataStorageService> _instance =
        new(() => new CropDataStorageService());

    public static CropDataStorageService Instance => _instance.Value;

    private const string StorageVersion = "2.0";
    private const string AppFolderName = "Cropaway";
    private const string CropDataFolderName = "crop-data";

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        WriteIndented = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    /// <summary>Thread-safety lock for file operations.</summary>
    private readonly object _fileLock = new();

    private CropDataStorageService() { }

    /// <summary>
    /// Gets the Application Data storage directory:
    /// %LocalAppData%/Cropaway/crop-data/
    /// </summary>
    private string StorageDirectory
    {
        get
        {
            string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            return Path.Combine(localAppData, AppFolderName, CropDataFolderName);
        }
    }

    /// <summary>
    /// Ensures the storage directory exists. Called during app startup.
    /// </summary>
    public void EnsureStorageDirectory()
    {
        Directory.CreateDirectory(StorageDirectory);
    }

    /// <summary>
    /// Computes a stable, filesystem-safe key for a video file (SHA256 of its full path).
    /// </summary>
    private static string StorageKey(string filePath)
    {
        string normalizedPath = Path.GetFullPath(filePath);
        byte[] hashBytes = SHA256.HashData(Encoding.UTF8.GetBytes(normalizedPath));
        return Convert.ToHexString(hashBytes).ToLowerInvariant();
    }

    #region Save

    /// <summary>
    /// Saves crop data for a video. Creates a timestamped JSON file in the storage directory.
    /// </summary>
    /// <param name="document">The crop data document to save.</param>
    /// <param name="sourceFilePath">The source video file path (used for keying).</param>
    public void Save(CropStorageDocument document, string sourceFilePath)
    {
        string json = JsonSerializer.Serialize(document, JsonOptions);
        byte[] data = Encoding.UTF8.GetBytes(json);

        lock (_fileLock)
        {
            EnsureStorageDirectory();

            string key = StorageKey(sourceFilePath);
            string timestamp = DateTime.Now.ToString("yyyy-MM-dd_HH-mm-ss");
            string fileName = $"{key}_{timestamp}.json";
            string filePath = Path.Combine(StorageDirectory, fileName);

            File.WriteAllBytes(filePath, data);
            Debug.WriteLine($"Crop data saved to: {filePath}");
        }
    }

    /// <summary>
    /// Creates a CropStorageDocument from the current crop state.
    /// </summary>
    public CropStorageDocument CreateDocument(
        string sourceFilePath,
        VideoMetadata metadata,
        CropMode mode,
        Rect cropRect,
        Point circleCenter,
        double circleRadius,
        List<Point>? freehandPoints,
        byte[]? freehandPathData,
        byte[]? aiMaskData,
        Rect aiBoundingBox,
        string? aiTextPrompt,
        double aiConfidence,
        List<KeyframeData>? keyframes,
        bool keyframesEnabled)
    {
        var source = new SourceInfo
        {
            FilePath = sourceFilePath,
            FileName = Path.GetFileName(sourceFilePath),
            Width = metadata.Width,
            Height = metadata.Height,
            Duration = metadata.Duration,
            FrameRate = metadata.FrameRate,
            Codec = metadata.CodecType ?? "",
            IsHDR = metadata.IsHDR,
            ColorSpace = metadata.ColorSpaceDescription,
            BitDepth = metadata.BitDepth,
            BitRate = metadata.BitRate
        };

        var cropData = new CropData { Mode = mode.ToString().ToLowerInvariant() };

        switch (mode)
        {
            case CropMode.Rectangle:
                cropData.Rectangle = new RectangleData
                {
                    X = cropRect.X,
                    Y = cropRect.Y,
                    Width = cropRect.Width,
                    Height = cropRect.Height
                };
                break;

            case CropMode.Circle:
                cropData.Circle = new CircleData
                {
                    CenterX = circleCenter.X,
                    CenterY = circleCenter.Y,
                    Radius = circleRadius
                };
                break;

            case CropMode.Freehand:
                if (freehandPoints is { Count: > 0 })
                {
                    // Try to extract bezier control handles from path data
                    List<VertexData>? bezierVertices = null;
                    if (freehandPathData is { Length: > 0 })
                    {
                        try
                        {
                            string pathJson = Encoding.UTF8.GetString(freehandPathData);
                            var parsed = JsonSerializer.Deserialize<List<JsonElement>>(pathJson);
                            if (parsed != null && parsed.Count == freehandPoints.Count)
                            {
                                bezierVertices = new List<VertexData>();
                                for (int i = 0; i < parsed.Count; i++)
                                {
                                    var elem = parsed[i];
                                    var vd = new VertexData
                                    {
                                        X = freehandPoints[i].X,
                                        Y = freehandPoints[i].Y
                                    };
                                    if (elem.TryGetProperty("controlInX", out var cix) && cix.ValueKind == JsonValueKind.Number)
                                        vd.ControlInX = cix.GetDouble();
                                    if (elem.TryGetProperty("controlInY", out var ciy) && ciy.ValueKind == JsonValueKind.Number)
                                        vd.ControlInY = ciy.GetDouble();
                                    if (elem.TryGetProperty("controlOutX", out var cox) && cox.ValueKind == JsonValueKind.Number)
                                        vd.ControlOutX = cox.GetDouble();
                                    if (elem.TryGetProperty("controlOutY", out var coy) && coy.ValueKind == JsonValueKind.Number)
                                        vd.ControlOutY = coy.GetDouble();
                                    bezierVertices.Add(vd);
                                }
                            }
                        }
                        catch { /* Fall back to simple points */ }
                    }

                    cropData.Freehand = new FreehandData
                    {
                        Vertices = bezierVertices ?? freehandPoints.Select(p => new VertexData
                        {
                            X = p.X,
                            Y = p.Y
                        }).ToList()
                    };
                }
                break;

            case CropMode.AI:
                cropData.AI = new AIData
                {
                    MaskDataBase64 = aiMaskData != null ? Convert.ToBase64String(aiMaskData) : null,
                    BoundingBoxX = aiBoundingBox.X,
                    BoundingBoxY = aiBoundingBox.Y,
                    BoundingBoxWidth = aiBoundingBox.Width,
                    BoundingBoxHeight = aiBoundingBox.Height,
                    TextPrompt = aiTextPrompt,
                    Confidence = aiConfidence
                };
                break;
        }

        // Keyframes
        if (keyframesEnabled && keyframes is { Count: > 1 })
        {
            cropData.Keyframes = keyframes.Select(kf => new KeyframeStorageData
            {
                Timestamp = kf.Timestamp,
                Interpolation = kf.Interpolation.ToString().ToLowerInvariant(),
                Rectangle = new RectangleData
                {
                    X = kf.CropRect.X,
                    Y = kf.CropRect.Y,
                    Width = kf.CropRect.Width,
                    Height = kf.CropRect.Height
                },
                Circle = new CircleData
                {
                    CenterX = kf.CircleCenter.X,
                    CenterY = kf.CircleCenter.Y,
                    Radius = kf.CircleRadius
                }
            }).ToList();
        }

        var outputBounds = new OutputBounds
        {
            CropPixelX = (int)(cropRect.X * metadata.Width),
            CropPixelY = (int)(cropRect.Y * metadata.Height),
            CropPixelWidth = (int)(cropRect.Width * metadata.Width),
            CropPixelHeight = (int)(cropRect.Height * metadata.Height),
            OriginalWidth = metadata.Width,
            OriginalHeight = metadata.Height
        };

        return new CropStorageDocument
        {
            Version = StorageVersion,
            SavedAt = DateTime.UtcNow,
            Source = source,
            Crop = cropData,
            OutputBounds = outputBounds
        };
    }

    #endregion

    #region Load

    /// <summary>
    /// Loads the most recent crop data for a video file.
    /// Returns null if no saved data exists.
    /// </summary>
    /// <param name="sourceFilePath">Path to the source video file.</param>
    /// <returns>The most recently saved crop document, or null.</returns>
    public CropStorageDocument? Load(string sourceFilePath)
    {
        lock (_fileLock)
        {
            string key = StorageKey(sourceFilePath);
            string prefix = $"{key}_";

            return LoadMostRecent(StorageDirectory, prefix);
        }
    }

    /// <summary>
    /// Loads the most recently modified JSON file with the given prefix.
    /// </summary>
    private CropStorageDocument? LoadMostRecent(string directory, string prefix)
    {
        if (!Directory.Exists(directory))
            return null;

        var matchingFiles = Directory.GetFiles(directory, "*.json")
            .Where(f => Path.GetFileName(f).StartsWith(prefix))
            .OrderByDescending(f => File.GetLastWriteTimeUtc(f))
            .ToList();

        foreach (string filePath in matchingFiles)
        {
            try
            {
                string json = File.ReadAllText(filePath, Encoding.UTF8);
                var doc = JsonSerializer.Deserialize<CropStorageDocument>(json, JsonOptions);
                if (doc != null)
                    return doc;
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Failed to load crop data from {filePath}: {ex.Message}");
            }
        }

        return null;
    }

    /// <summary>
    /// Applies loaded crop data to a set of output variables.
    /// Returns the crop mode and populates all output parameters.
    /// </summary>
    public CropMode Apply(
        CropStorageDocument document,
        out Rect cropRect,
        out Point circleCenter,
        out double circleRadius,
        out List<Point> freehandPoints,
        out byte[]? freehandPathData,
        out byte[]? aiMaskData,
        out Rect aiBoundingBox,
        out string? aiTextPrompt,
        out double aiConfidence,
        out List<KeyframeData> keyframes,
        out bool keyframesEnabled)
    {
        // Defaults
        cropRect = new Rect(0, 0, 1, 1);
        circleCenter = new Point(0.5, 0.5);
        circleRadius = 0.4;
        freehandPoints = new List<Point>();
        freehandPathData = null;
        aiMaskData = null;
        aiBoundingBox = Rect.Empty;
        aiTextPrompt = null;
        aiConfidence = 0;
        keyframes = new List<KeyframeData>();
        keyframesEnabled = false;

        // Parse mode
        CropMode mode = CropMode.Rectangle;
        if (Enum.TryParse<CropMode>(document.Crop.Mode, ignoreCase: true, out var parsedMode))
            mode = parsedMode;

        // Rectangle
        if (document.Crop.Rectangle is { } rect)
        {
            cropRect = new Rect(rect.X, rect.Y, rect.Width, rect.Height);
        }

        // Circle
        if (document.Crop.Circle is { } circle)
        {
            circleCenter = new Point(circle.CenterX, circle.CenterY);
            circleRadius = circle.Radius;
        }

        // Freehand
        if (document.Crop.Freehand?.Vertices is { Count: > 0 } vertices)
        {
            freehandPoints = vertices.Select(v => new Point(v.X, v.Y)).ToList();

            // Reconstruct bezier path data from VertexData control handles
            bool hasControlHandles = vertices.Any(v =>
                v.ControlInX.HasValue || v.ControlInY.HasValue ||
                v.ControlOutX.HasValue || v.ControlOutY.HasValue);

            if (hasControlHandles)
            {
                var serializedVertices = vertices.Select(v => new
                {
                    id = Guid.NewGuid(),
                    positionX = v.X,
                    positionY = v.Y,
                    controlInX = v.ControlInX,
                    controlInY = v.ControlInY,
                    controlOutX = v.ControlOutX,
                    controlOutY = v.ControlOutY
                }).ToList();

                string json = JsonSerializer.Serialize(serializedVertices);
                freehandPathData = Encoding.UTF8.GetBytes(json);
            }
        }

        // AI
        if (document.Crop.AI is { } ai)
        {
            if (!string.IsNullOrEmpty(ai.MaskDataBase64))
                aiMaskData = Convert.FromBase64String(ai.MaskDataBase64);

            aiBoundingBox = new Rect(
                ai.BoundingBoxX, ai.BoundingBoxY,
                ai.BoundingBoxWidth, ai.BoundingBoxHeight);
            aiTextPrompt = ai.TextPrompt;
            aiConfidence = ai.Confidence;
        }

        // Keyframes
        if (document.Crop.Keyframes is { Count: > 0 } kfList)
        {
            keyframesEnabled = kfList.Count > 1;
            keyframes = kfList.Select(kf =>
            {
                var kfData = new KeyframeData
                {
                    Timestamp = kf.Timestamp,
                    Interpolation = Enum.TryParse<KeyframeInterpolation>(
                        kf.Interpolation, ignoreCase: true, out var interp)
                        ? interp
                        : KeyframeInterpolation.Linear
                };

                if (kf.Rectangle is { } kfRect)
                    kfData.CropRect = new Rect(kfRect.X, kfRect.Y, kfRect.Width, kfRect.Height);

                if (kf.Circle is { } kfCircle)
                {
                    kfData.CircleCenter = new Point(kfCircle.CenterX, kfCircle.CenterY);
                    kfData.CircleRadius = kfCircle.Radius;
                }

                if (kf.AI is { } kfAi)
                {
                    if (!string.IsNullOrEmpty(kfAi.MaskDataBase64))
                        kfData.AIMaskData = Convert.FromBase64String(kfAi.MaskDataBase64);

                    kfData.AIBoundingBox = new Rect(
                        kfAi.BoundingBoxX, kfAi.BoundingBoxY,
                        kfAi.BoundingBoxWidth, kfAi.BoundingBoxHeight);
                }

                return kfData;
            }).ToList();
        }

        return mode;
    }

    #endregion

    #region Export

    /// <summary>
    /// Exports crop data to a user-chosen folder.
    /// </summary>
    /// <param name="document">The crop document to export.</param>
    /// <param name="destinationFolder">Target folder path.</param>
    /// <param name="videoFileName">Source video file name (used to name the output file).</param>
    /// <returns>Path to the exported JSON file.</returns>
    public string ExportToFolder(CropStorageDocument document, string destinationFolder, string videoFileName)
    {
        string json = JsonSerializer.Serialize(document, JsonOptions);

        string baseName = Path.GetFileNameWithoutExtension(videoFileName);
        string fileName = $"{baseName}_crop.json";
        string filePath = Path.Combine(destinationFolder, fileName);

        // Overwrite if exists
        File.WriteAllText(filePath, json, Encoding.UTF8);

        Debug.WriteLine($"Crop data exported to: {filePath}");
        return filePath;
    }

    #endregion

    #region Management

    /// <summary>
    /// Lists all crop data files for a given video.
    /// </summary>
    public List<string> ListFiles(string sourceFilePath)
    {
        lock (_fileLock)
        {
            string key = StorageKey(sourceFilePath);
            string prefix = $"{key}_";

            if (!Directory.Exists(StorageDirectory))
                return new List<string>();

            return Directory.GetFiles(StorageDirectory, "*.json")
                .Where(f => Path.GetFileName(f).StartsWith(prefix))
                .OrderByDescending(f => File.GetLastWriteTimeUtc(f))
                .ToList();
        }
    }

    /// <summary>
    /// Deletes all saved crop data for a video.
    /// </summary>
    public void DeleteAll(string sourceFilePath)
    {
        lock (_fileLock)
        {
            foreach (string file in ListFiles(sourceFilePath))
            {
                try { File.Delete(file); }
                catch (Exception ex)
                {
                    Debug.WriteLine($"Failed to delete crop data file {file}: {ex.Message}");
                }
            }
        }
    }

    #endregion
}
