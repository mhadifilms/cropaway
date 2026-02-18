// BoundingBoxExportService.cs
// CropawayWindows

using System.IO;
using System.Text.Json;
using System.Windows;
using CropawayWindows.Models;

namespace CropawayWindows.Services;

/// <summary>
/// Exports per-frame bounding box data from crop configurations for ML/AI pipelines.
/// Supports JSON and Python pickle (protocol 4) output formats.
/// Each frame's bounding box is represented as [x1, y1, x2, y2] in pixel coordinates.
/// </summary>
public sealed class BoundingBoxExportService
{
    /// <summary>
    /// Exports bounding box data as a JSON file containing a list of [x1, y1, x2, y2] arrays.
    /// </summary>
    /// <param name="config">The crop configuration with mode, coordinates, and keyframes.</param>
    /// <param name="metadata">Video metadata providing dimensions, duration, and frame rate.</param>
    /// <param name="outputPath">Full path for the output .json file.</param>
    public void ExportAsJson(CropConfiguration config, VideoMetadata metadata, string outputPath)
    {
        var boxes = GenerateBoundingBoxes(config, metadata);

        var options = new JsonSerializerOptions
        {
            WriteIndented = false
        };

        string json = JsonSerializer.Serialize(boxes, options);
        File.WriteAllText(outputPath, json);
    }

    /// <summary>
    /// Exports bounding box data as a Python pickle (protocol 4) file containing a list of lists of floats.
    /// </summary>
    /// <param name="config">The crop configuration with mode, coordinates, and keyframes.</param>
    /// <param name="metadata">Video metadata providing dimensions, duration, and frame rate.</param>
    /// <param name="outputPath">Full path for the output .pkl file.</param>
    public void ExportAsPickle(CropConfiguration config, VideoMetadata metadata, string outputPath)
    {
        var boxes = GenerateBoundingBoxes(config, metadata);
        byte[] pickleData = WritePickleProtocol4(boxes);
        File.WriteAllBytes(outputPath, pickleData);
    }

    /// <summary>
    /// Generates per-frame bounding boxes in pixel coordinates from the crop configuration.
    /// Uses keyframe interpolation when keyframes are present, otherwise uses the static crop state.
    /// </summary>
    private List<double[]> GenerateBoundingBoxes(CropConfiguration config, VideoMetadata metadata)
    {
        int totalFrames = metadata.TotalFrameCount;
        if (totalFrames <= 0) totalFrames = 1;

        double frameRate = metadata.FrameRate > 0 ? metadata.FrameRate : 30.0;
        int width = metadata.Width;
        int height = metadata.Height;
        var boxes = new List<double[]>(totalFrames);

        bool useKeyframes = config.HasKeyframes;

        if (useKeyframes)
        {
            // Convert Keyframe objects to KeyframeData for the interpolator
            var keyframeDataList = config.Keyframes
                .Select(kf => new KeyframeData
                {
                    Timestamp = kf.Timestamp,
                    CropRect = kf.CropRect,
                    EdgeInsets = kf.EdgeInsets,
                    CircleCenter = kf.CircleCenter,
                    CircleRadius = kf.CircleRadius,
                    FreehandPathData = kf.FreehandPathData,
                    AIMaskData = kf.AiMaskData,
                    AIBoundingBox = kf.AiBoundingBox,
                    Interpolation = kf.Interpolation
                })
                .ToList();

            var interpolator = KeyframeInterpolator.Instance;

            for (int frame = 0; frame < totalFrames; frame++)
            {
                double timestamp = frame / frameRate;
                var state = interpolator.Interpolate(keyframeDataList, timestamp, config.Mode);
                double[] box = ComputePixelBoundingBox(state, config.Mode, width, height);
                boxes.Add(box);
            }
        }
        else
        {
            // Static crop: same bounding box for every frame
            double[] box = ComputeStaticPixelBoundingBox(config, width, height);
            for (int frame = 0; frame < totalFrames; frame++)
            {
                boxes.Add(box);
            }
        }

        return boxes;
    }

    /// <summary>
    /// Computes the pixel bounding box [x1, y1, x2, y2] from an interpolated crop state.
    /// </summary>
    private static double[] ComputePixelBoundingBox(
        InterpolatedCropState state, CropMode mode, int width, int height)
    {
        Rect normalizedRect;

        switch (mode)
        {
            case CropMode.Rectangle:
                normalizedRect = state.CropRect;
                break;

            case CropMode.Circle:
            {
                double cx = state.CircleCenter.X;
                double cy = state.CircleCenter.Y;
                double r = state.CircleRadius;
                // CircleRadius is relative to min dimension in normalized space
                // Compute bounding box in normalized coordinates
                normalizedRect = new Rect(cx - r, cy - r, r * 2, r * 2);
                break;
            }

            case CropMode.AI:
            {
                if (state.AIBoundingBox.Width > 0 && state.AIBoundingBox.Height > 0)
                {
                    normalizedRect = state.AIBoundingBox;
                }
                else
                {
                    // Fall back to crop rect
                    normalizedRect = state.CropRect;
                }
                break;
            }

            case CropMode.Freehand:
            default:
                normalizedRect = state.CropRect;
                break;
        }

        return NormalizedRectToPixelBox(normalizedRect, width, height);
    }

    /// <summary>
    /// Computes the pixel bounding box [x1, y1, x2, y2] from a static (non-keyframed) crop configuration.
    /// </summary>
    private static double[] ComputeStaticPixelBoundingBox(CropConfiguration config, int width, int height)
    {
        Rect normalizedRect;

        switch (config.Mode)
        {
            case CropMode.Rectangle:
                normalizedRect = config.CropRect;
                break;

            case CropMode.Circle:
            {
                double cx = config.CircleCenter.X;
                double cy = config.CircleCenter.Y;
                double r = config.CircleRadius;
                normalizedRect = new Rect(cx - r, cy - r, r * 2, r * 2);
                break;
            }

            case CropMode.AI:
            {
                if (config.AiBoundingBox.Width > 0 && config.AiBoundingBox.Height > 0)
                {
                    normalizedRect = config.AiBoundingBox;
                }
                else
                {
                    normalizedRect = config.CropRect;
                }
                break;
            }

            case CropMode.Freehand:
            default:
                normalizedRect = config.CropRect;
                break;
        }

        return NormalizedRectToPixelBox(normalizedRect, width, height);
    }

    /// <summary>
    /// Converts a normalized (0-1) rectangle to pixel coordinates [x1, y1, x2, y2].
    /// </summary>
    private static double[] NormalizedRectToPixelBox(Rect normalized, int width, int height)
    {
        double x1 = normalized.X * width;
        double y1 = normalized.Y * height;
        double x2 = (normalized.X + normalized.Width) * width;
        double y2 = (normalized.Y + normalized.Height) * height;
        return [x1, y1, x2, y2];
    }

    #region Python Pickle Protocol 4 Writer

    // Python pickle opcodes used
    private const byte PROTO = 0x80;           // Protocol version indicator
    private const byte FRAME = 0x95;           // Framing for protocol 4
    private const byte EMPTY_LIST = 0x5D;      // Push empty list
    private const byte MARK = 0x28;            // Push mark onto stack
    private const byte APPENDS = 0x65;         // Extend list from stack slice
    private const byte BINFLOAT = 0x47;        // Push 8-byte IEEE 754 float
    private const byte STOP = 0x2E;            // End of pickle

    /// <summary>
    /// Writes a list of lists of doubles as Python pickle protocol 4 binary data.
    /// Produces a pickle equivalent to: [[x1, y1, x2, y2], [x1, y1, x2, y2], ...]
    /// </summary>
    private static byte[] WritePickleProtocol4(List<double[]> boxes)
    {
        using var stream = new MemoryStream();
        using var writer = new BinaryWriter(stream);

        // Phase 1: Build the pickle body into a separate buffer so we can compute
        // the FRAME length.
        byte[] body = BuildPickleBody(boxes);

        // Protocol 4 header
        writer.Write(PROTO);
        writer.Write((byte)4); // protocol version 4

        // FRAME opcode followed by 8-byte little-endian length of the remaining data
        writer.Write(FRAME);
        writer.Write((long)body.Length);

        // Write the body
        writer.Write(body);

        return stream.ToArray();
    }

    /// <summary>
    /// Builds the pickle body (everything after the FRAME header):
    /// EMPTY_LIST MARK { EMPTY_LIST MARK BINFLOAT*4 APPENDS }* APPENDS STOP
    /// </summary>
    private static byte[] BuildPickleBody(List<double[]> boxes)
    {
        using var stream = new MemoryStream();
        using var writer = new BinaryWriter(stream);

        // Outer list
        writer.Write(EMPTY_LIST);    // Push empty outer list
        writer.Write(MARK);          // Mark for APPENDS to outer list

        foreach (var box in boxes)
        {
            // Inner list for this frame's bounding box
            writer.Write(EMPTY_LIST);  // Push empty inner list
            writer.Write(MARK);        // Mark for APPENDS to inner list

            foreach (double value in box)
            {
                writer.Write(BINFLOAT);
                // BINFLOAT expects 8 bytes in big-endian (network) byte order
                byte[] floatBytes = BitConverter.GetBytes(value);
                if (BitConverter.IsLittleEndian)
                    Array.Reverse(floatBytes);
                writer.Write(floatBytes);
            }

            writer.Write(APPENDS);     // Extend inner list with marked values
        }

        writer.Write(APPENDS);        // Extend outer list with all inner lists
        writer.Write(STOP);           // End of pickle

        return stream.ToArray();
    }

    #endregion
}
