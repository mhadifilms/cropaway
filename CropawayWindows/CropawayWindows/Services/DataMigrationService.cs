// DataMigrationService.cs
// CropawayWindows

using System.Diagnostics;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using CropawayWindows.Models;

namespace CropawayWindows.Services;

/// <summary>
/// Migrates legacy .cropaway sidecar data to the centralized %LocalAppData% storage.
/// Checks three legacy formats:
///   1. .cropaway/ folder next to the video containing JSON files matching the video name
///   2. video.mp4.cropaway direct sidecar file
///   3. video.mp4.cropaway.json sidecar file next to the video
///
/// Singleton. Thread-safe. Never deletes legacy data on migration.
/// </summary>
public sealed class DataMigrationService
{
    private static readonly Lazy<DataMigrationService> _instance =
        new(() => new DataMigrationService());

    public static DataMigrationService Instance => _instance.Value;

    private static readonly JsonSerializerOptions JsonOptions = new()
    {
        PropertyNameCaseInsensitive = true,
        DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
    };

    /// <summary>
    /// Tracks which video paths have already been checked during this session
    /// to avoid redundant filesystem scans.
    /// </summary>
    private readonly HashSet<string> _checkedPaths = new(StringComparer.OrdinalIgnoreCase);
    private readonly object _lock = new();

    private DataMigrationService() { }

    /// <summary>
    /// Checks for legacy sidecar crop data next to the video file and migrates it
    /// to the new centralized storage location if found.
    /// Returns the migrated document if legacy data was found and successfully parsed,
    /// or null if no legacy data exists or migration was not needed.
    /// </summary>
    /// <param name="videoPath">Full path to the video file.</param>
    /// <returns>The migrated CropStorageDocument, or null.</returns>
    public CropStorageDocument? MigrateIfNeeded(string videoPath)
    {
        if (string.IsNullOrWhiteSpace(videoPath))
            return null;

        lock (_lock)
        {
            string normalizedPath = Path.GetFullPath(videoPath);

            // Skip if already checked this session
            if (!_checkedPaths.Add(normalizedPath))
                return null;
        }

        try
        {
            string? directory = Path.GetDirectoryName(videoPath);
            if (string.IsNullOrEmpty(directory) || !Directory.Exists(directory))
                return null;

            string fileName = Path.GetFileName(videoPath);
            string fileNameWithoutExt = Path.GetFileNameWithoutExtension(videoPath);

            // Try each legacy format in order of likelihood
            string? legacyJson = null;
            string? legacySourcePath = null;

            // 1. Check .cropaway/ folder next to the video
            legacyJson = TryLoadFromCropawayFolder(directory, fileName, fileNameWithoutExt, out legacySourcePath);

            // 2. Check video.mp4.cropaway direct sidecar
            if (legacyJson == null)
            {
                legacyJson = TryLoadFromSidecarFile(
                    Path.Combine(directory, fileName + ".cropaway"),
                    out legacySourcePath);
            }

            // 3. Check video.mp4.cropaway.json sidecar
            if (legacyJson == null)
            {
                legacyJson = TryLoadFromSidecarFile(
                    Path.Combine(directory, fileName + ".cropaway.json"),
                    out legacySourcePath);
            }

            if (legacyJson == null)
                return null;

            // Parse and convert
            var document = ParseLegacyJson(legacyJson, videoPath);
            if (document == null)
            {
                Debug.WriteLine($"[DataMigration] Failed to parse legacy data from: {legacySourcePath}");
                return null;
            }

            // Save to the new centralized storage
            CropDataStorageService.Instance.Save(document, videoPath);
            Debug.WriteLine($"[DataMigration] Successfully migrated legacy data for: {fileName} (from {legacySourcePath})");

            return document;
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[DataMigration] Error during migration for {videoPath}: {ex.Message}");
            return null;
        }
    }

    /// <summary>
    /// Batch-migrates legacy data for multiple video paths.
    /// Returns a dictionary of video paths to their migrated documents (only those that had legacy data).
    /// </summary>
    /// <param name="videoPaths">Collection of video file paths to check.</param>
    /// <returns>Dictionary mapping video paths to their migrated CropStorageDocuments.</returns>
    public Dictionary<string, CropStorageDocument> MigrateAll(IEnumerable<string> videoPaths)
    {
        var results = new Dictionary<string, CropStorageDocument>(StringComparer.OrdinalIgnoreCase);

        foreach (string videoPath in videoPaths)
        {
            try
            {
                var document = MigrateIfNeeded(videoPath);
                if (document != null)
                {
                    results[videoPath] = document;
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"[DataMigration] Batch migration error for {videoPath}: {ex.Message}");
            }
        }

        if (results.Count > 0)
        {
            Debug.WriteLine($"[DataMigration] Batch migration complete: {results.Count} file(s) migrated");
        }

        return results;
    }

    /// <summary>
    /// Resets the set of already-checked paths, allowing re-checking on next call.
    /// Useful if the user moves files or wants to force a re-scan.
    /// </summary>
    public void ResetCheckedPaths()
    {
        lock (_lock)
        {
            _checkedPaths.Clear();
        }
    }

    #region Legacy Format Loading

    /// <summary>
    /// Looks inside a .cropaway/ folder next to the video for JSON files
    /// matching the video filename.
    /// </summary>
    private static string? TryLoadFromCropawayFolder(
        string videoDirectory,
        string videoFileName,
        string videoFileNameWithoutExt,
        out string? sourcePath)
    {
        sourcePath = null;

        string cropawayFolder = Path.Combine(videoDirectory, ".cropaway");
        if (!Directory.Exists(cropawayFolder))
            return null;

        try
        {
            // Look for JSON files that match the video filename
            // Possible naming patterns:
            //   videoname.json
            //   videoname.mp4.json
            //   videoname_crop.json
            //   Any .json file containing the video name
            string[] candidates =
            {
                Path.Combine(cropawayFolder, videoFileNameWithoutExt + ".json"),
                Path.Combine(cropawayFolder, videoFileName + ".json"),
                Path.Combine(cropawayFolder, videoFileNameWithoutExt + "_crop.json"),
            };

            foreach (string candidate in candidates)
            {
                if (File.Exists(candidate))
                {
                    string json = File.ReadAllText(candidate, Encoding.UTF8);
                    if (!string.IsNullOrWhiteSpace(json))
                    {
                        sourcePath = candidate;
                        Debug.WriteLine($"[DataMigration] Found legacy data in .cropaway folder: {candidate}");
                        return json;
                    }
                }
            }

            // Fallback: scan all JSON files in the folder for one matching the video name
            var jsonFiles = Directory.GetFiles(cropawayFolder, "*.json")
                .OrderByDescending(f => File.GetLastWriteTimeUtc(f))
                .ToList();

            foreach (string jsonFile in jsonFiles)
            {
                string jsonFileName = Path.GetFileNameWithoutExtension(jsonFile);
                if (jsonFileName.Contains(videoFileNameWithoutExt, StringComparison.OrdinalIgnoreCase))
                {
                    string json = File.ReadAllText(jsonFile, Encoding.UTF8);
                    if (!string.IsNullOrWhiteSpace(json))
                    {
                        sourcePath = jsonFile;
                        Debug.WriteLine($"[DataMigration] Found legacy data via name match in .cropaway folder: {jsonFile}");
                        return json;
                    }
                }
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[DataMigration] Error scanning .cropaway folder at {cropawayFolder}: {ex.Message}");
        }

        return null;
    }

    /// <summary>
    /// Tries to read a direct sidecar file (e.g. video.mp4.cropaway or video.mp4.cropaway.json).
    /// </summary>
    private static string? TryLoadFromSidecarFile(string sidecarPath, out string? sourcePath)
    {
        sourcePath = null;

        try
        {
            if (!File.Exists(sidecarPath))
                return null;

            string json = File.ReadAllText(sidecarPath, Encoding.UTF8);
            if (!string.IsNullOrWhiteSpace(json))
            {
                sourcePath = sidecarPath;
                Debug.WriteLine($"[DataMigration] Found legacy sidecar: {sidecarPath}");
                return json;
            }
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[DataMigration] Error reading sidecar {sidecarPath}: {ex.Message}");
        }

        return null;
    }

    #endregion

    #region Legacy JSON Parsing

    /// <summary>
    /// Parses legacy JSON into a current-format CropStorageDocument.
    /// Handles both v1.0 and v2.0 formats defensively.
    /// </summary>
    private static CropStorageDocument? ParseLegacyJson(string json, string videoPath)
    {
        try
        {
            using var jsonDoc = JsonDocument.Parse(json);
            var root = jsonDoc.RootElement;

            // Detect version
            string version = "1.0";
            if (root.TryGetProperty("version", out var versionProp))
            {
                version = versionProp.GetString() ?? "1.0";
            }

            // If it's already v2.0, just deserialize directly
            if (version == "2.0")
            {
                return JsonSerializer.Deserialize<CropStorageDocument>(json, JsonOptions);
            }

            // Parse v1.0 format into v2.0
            return ParseVersion1(root, videoPath);
        }
        catch (JsonException ex)
        {
            Debug.WriteLine($"[DataMigration] JSON parse error: {ex.Message}");
            return null;
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[DataMigration] Unexpected parse error: {ex.Message}");
            return null;
        }
    }

    /// <summary>
    /// Converts a v1.0 legacy document to the current v2.0 format.
    /// The v1.0 format may use slightly different property names or structure.
    /// This method handles variations defensively.
    /// </summary>
    private static CropStorageDocument? ParseVersion1(JsonElement root, string videoPath)
    {
        var document = new CropStorageDocument
        {
            Version = "2.0",
            SavedAt = DateTime.UtcNow
        };

        // Source info
        document.Source = new SourceInfo
        {
            FilePath = videoPath,
            FileName = Path.GetFileName(videoPath)
        };

        // Try to read source metadata from legacy format
        if (root.TryGetProperty("source", out var sourceElem))
        {
            ReadSourceInfo(sourceElem, document.Source);
        }

        // Crop data
        document.Crop = new CropData();

        // Mode - could be at top level or inside "crop" object
        string mode = "rectangle";
        if (root.TryGetProperty("mode", out var modeProp))
        {
            mode = modeProp.GetString()?.ToLowerInvariant() ?? "rectangle";
        }
        else if (root.TryGetProperty("crop", out var cropElem) &&
                 cropElem.TryGetProperty("mode", out var cropModeProp))
        {
            mode = cropModeProp.GetString()?.ToLowerInvariant() ?? "rectangle";
        }
        document.Crop.Mode = mode;

        // Find the crop data element - could be at root or nested under "crop"
        JsonElement cropRoot = root;
        if (root.TryGetProperty("crop", out var cropContainer))
        {
            cropRoot = cropContainer;
        }

        // Rectangle
        document.Crop.Rectangle = TryParseRectangle(cropRoot);

        // Circle
        document.Crop.Circle = TryParseCircle(cropRoot);

        // Freehand
        document.Crop.Freehand = TryParseFreehand(cropRoot);

        // AI
        document.Crop.AI = TryParseAI(cropRoot);

        // Keyframes
        document.Crop.Keyframes = TryParseKeyframes(cropRoot);

        // Output bounds
        document.OutputBounds = TryParseOutputBounds(root) ?? new OutputBounds();

        return document;
    }

    private static void ReadSourceInfo(JsonElement elem, SourceInfo source)
    {
        if (elem.TryGetProperty("filePath", out var fp))
            source.FilePath = fp.GetString() ?? source.FilePath;
        if (elem.TryGetProperty("fileName", out var fn))
            source.FileName = fn.GetString() ?? source.FileName;
        if (elem.TryGetProperty("width", out var w) && w.TryGetInt32(out int width))
            source.Width = width;
        if (elem.TryGetProperty("height", out var h) && h.TryGetInt32(out int height))
            source.Height = height;
        if (elem.TryGetProperty("duration", out var d) && d.TryGetDouble(out double duration))
            source.Duration = duration;
        if (elem.TryGetProperty("frameRate", out var fr) && fr.TryGetDouble(out double frameRate))
            source.FrameRate = frameRate;
        if (elem.TryGetProperty("codec", out var c))
            source.Codec = c.GetString() ?? "";
        if (elem.TryGetProperty("isHDR", out var hdr))
            source.IsHDR = hdr.ValueKind == JsonValueKind.True;
        if (elem.TryGetProperty("colorSpace", out var cs))
            source.ColorSpace = cs.GetString();
        if (elem.TryGetProperty("bitDepth", out var bd) && bd.TryGetInt32(out int bitDepth))
            source.BitDepth = bitDepth;
        if (elem.TryGetProperty("bitRate", out var br) && br.TryGetInt64(out long bitRate))
            source.BitRate = bitRate;
    }

    private static RectangleData? TryParseRectangle(JsonElement cropRoot)
    {
        JsonElement rectElem;

        if (cropRoot.TryGetProperty("rectangle", out rectElem))
        {
            // Standard nested format: { "rectangle": { "x": ..., "y": ..., ... } }
        }
        else if (cropRoot.TryGetProperty("cropRect", out rectElem))
        {
            // Legacy property name variant
        }
        else if (cropRoot.TryGetProperty("rect", out rectElem))
        {
            // Another legacy variant
        }
        else
        {
            // Try top-level x/y/width/height (flat format)
            if (cropRoot.TryGetProperty("x", out _) && cropRoot.TryGetProperty("y", out _))
            {
                rectElem = cropRoot;
            }
            else
            {
                return null;
            }
        }

        try
        {
            double x = GetDouble(rectElem, "x", 0);
            double y = GetDouble(rectElem, "y", 0);
            double w = GetDouble(rectElem, "width", 1);
            double h = GetDouble(rectElem, "height", 1);

            return new RectangleData { X = x, Y = y, Width = w, Height = h };
        }
        catch
        {
            return null;
        }
    }

    private static CircleData? TryParseCircle(JsonElement cropRoot)
    {
        if (!cropRoot.TryGetProperty("circle", out var circleElem))
            return null;

        try
        {
            double cx = GetDouble(circleElem, "centerX", 0.5);
            double cy = GetDouble(circleElem, "centerY", 0.5);
            double r = GetDouble(circleElem, "radius", 0.4);

            return new CircleData { CenterX = cx, CenterY = cy, Radius = r };
        }
        catch
        {
            return null;
        }
    }

    private static FreehandData? TryParseFreehand(JsonElement cropRoot)
    {
        if (!cropRoot.TryGetProperty("freehand", out var freehandElem))
            return null;

        try
        {
            // Try "vertices" array (standard format)
            if (freehandElem.TryGetProperty("vertices", out var verticesArr) &&
                verticesArr.ValueKind == JsonValueKind.Array)
            {
                var vertices = new List<VertexData>();
                foreach (var v in verticesArr.EnumerateArray())
                {
                    var vertex = new VertexData
                    {
                        X = GetDouble(v, "x", 0),
                        Y = GetDouble(v, "y", 0)
                    };

                    if (v.TryGetProperty("controlInX", out var cix) && cix.ValueKind == JsonValueKind.Number)
                        vertex.ControlInX = cix.GetDouble();
                    if (v.TryGetProperty("controlInY", out var ciy) && ciy.ValueKind == JsonValueKind.Number)
                        vertex.ControlInY = ciy.GetDouble();
                    if (v.TryGetProperty("controlOutX", out var cox) && cox.ValueKind == JsonValueKind.Number)
                        vertex.ControlOutX = cox.GetDouble();
                    if (v.TryGetProperty("controlOutY", out var coy) && coy.ValueKind == JsonValueKind.Number)
                        vertex.ControlOutY = coy.GetDouble();

                    vertices.Add(vertex);
                }

                if (vertices.Count > 0)
                    return new FreehandData { Vertices = vertices };
            }

            // Try "points" array (legacy format - simple x/y pairs)
            if (freehandElem.TryGetProperty("points", out var pointsArr) &&
                pointsArr.ValueKind == JsonValueKind.Array)
            {
                var vertices = new List<VertexData>();
                foreach (var p in pointsArr.EnumerateArray())
                {
                    vertices.Add(new VertexData
                    {
                        X = GetDouble(p, "x", 0),
                        Y = GetDouble(p, "y", 0)
                    });
                }

                if (vertices.Count > 0)
                    return new FreehandData { Vertices = vertices };
            }
        }
        catch
        {
            // Freehand parse failed, skip
        }

        return null;
    }

    private static AIData? TryParseAI(JsonElement cropRoot)
    {
        if (!cropRoot.TryGetProperty("ai", out var aiElem))
            return null;

        try
        {
            var ai = new AIData
            {
                BoundingBoxX = GetDouble(aiElem, "boundingBoxX", 0),
                BoundingBoxY = GetDouble(aiElem, "boundingBoxY", 0),
                BoundingBoxWidth = GetDouble(aiElem, "boundingBoxWidth", 0),
                BoundingBoxHeight = GetDouble(aiElem, "boundingBoxHeight", 0),
                Confidence = GetDouble(aiElem, "confidence", 0)
            };

            if (aiElem.TryGetProperty("maskDataBase64", out var maskProp) &&
                maskProp.ValueKind == JsonValueKind.String)
            {
                ai.MaskDataBase64 = maskProp.GetString();
            }

            if (aiElem.TryGetProperty("textPrompt", out var promptProp) &&
                promptProp.ValueKind == JsonValueKind.String)
            {
                ai.TextPrompt = promptProp.GetString();
            }

            if (aiElem.TryGetProperty("promptPoints", out var pointsArr) &&
                pointsArr.ValueKind == JsonValueKind.Array)
            {
                ai.PromptPoints = new List<AIPromptPointData>();
                foreach (var p in pointsArr.EnumerateArray())
                {
                    ai.PromptPoints.Add(new AIPromptPointData
                    {
                        X = GetDouble(p, "x", 0),
                        Y = GetDouble(p, "y", 0),
                        IsPositive = p.TryGetProperty("isPositive", out var ip) &&
                                     ip.ValueKind == JsonValueKind.True
                    });
                }
            }

            return ai;
        }
        catch
        {
            return null;
        }
    }

    private static List<KeyframeStorageData>? TryParseKeyframes(JsonElement cropRoot)
    {
        if (!cropRoot.TryGetProperty("keyframes", out var kfArr) ||
            kfArr.ValueKind != JsonValueKind.Array)
            return null;

        try
        {
            var keyframes = new List<KeyframeStorageData>();

            foreach (var kfElem in kfArr.EnumerateArray())
            {
                var kf = new KeyframeStorageData
                {
                    Timestamp = GetDouble(kfElem, "timestamp", 0),
                    Interpolation = "linear"
                };

                if (kfElem.TryGetProperty("interpolation", out var interpProp) &&
                    interpProp.ValueKind == JsonValueKind.String)
                {
                    kf.Interpolation = interpProp.GetString()?.ToLowerInvariant() ?? "linear";
                }

                kf.Rectangle = TryParseRectangle(kfElem);
                kf.Circle = TryParseCircle(kfElem);
                kf.Freehand = TryParseFreehand(kfElem);
                kf.AI = TryParseAI(kfElem);

                keyframes.Add(kf);
            }

            return keyframes.Count > 0 ? keyframes : null;
        }
        catch
        {
            return null;
        }
    }

    private static OutputBounds? TryParseOutputBounds(JsonElement root)
    {
        if (!root.TryGetProperty("outputBounds", out var obElem))
            return null;

        try
        {
            return new OutputBounds
            {
                CropPixelX = GetInt(obElem, "cropPixelX", 0),
                CropPixelY = GetInt(obElem, "cropPixelY", 0),
                CropPixelWidth = GetInt(obElem, "cropPixelWidth", 0),
                CropPixelHeight = GetInt(obElem, "cropPixelHeight", 0),
                OriginalWidth = GetInt(obElem, "originalWidth", 0),
                OriginalHeight = GetInt(obElem, "originalHeight", 0)
            };
        }
        catch
        {
            return null;
        }
    }

    #endregion

    #region JSON Helpers

    private static double GetDouble(JsonElement elem, string propertyName, double defaultValue)
    {
        if (elem.TryGetProperty(propertyName, out var prop) && prop.TryGetDouble(out double value))
            return value;
        return defaultValue;
    }

    private static int GetInt(JsonElement elem, string propertyName, int defaultValue)
    {
        if (elem.TryGetProperty(propertyName, out var prop) && prop.TryGetInt32(out int value))
            return value;
        return defaultValue;
    }

    #endregion
}
