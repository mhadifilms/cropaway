// CropMaskRenderer.cs
// CropawayWindows

using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Text.Json;
using System.Windows;
using CropawayWindows.Models;

// Note: This file uses System.Drawing for GDI+ bitmap operations.
// Brush and Rectangle are fully qualified below to avoid conflict
// with global using aliases (which point to WPF types).

namespace CropawayWindows.Services;

/// <summary>
/// Serialized mask vertex with bezier control handles.
/// Mirrors the MaskVertex Swift struct for path data deserialization.
/// </summary>
internal class SerializedMaskVertex
{
    public Guid id { get; set; }
    public double positionX { get; set; }
    public double positionY { get; set; }
    public double? controlInX { get; set; }
    public double? controlInY { get; set; }
    public double? controlOutX { get; set; }
    public double? controlOutY { get; set; }
}

/// <summary>
/// Generates mask images for circle, freehand, and AI crop modes.
/// Uses System.Drawing.Common for bitmap creation and rendering.
/// All coordinates are expected in normalized 0-1 space.
/// </summary>
public static class CropMaskRenderer
{
    /// <summary>
    /// Generates a PNG mask image for the given crop mode and parameters.
    /// White pixels represent the visible (unmasked) area, black pixels are masked out.
    /// </summary>
    /// <param name="mode">The crop mode.</param>
    /// <param name="width">Target mask width in pixels.</param>
    /// <param name="height">Target mask height in pixels.</param>
    /// <param name="cropRect">Normalized crop rectangle (0-1).</param>
    /// <param name="circleCenter">Normalized circle center (0-1).</param>
    /// <param name="circleRadius">Normalized circle radius (0-1, relative to min dimension).</param>
    /// <param name="freehandPoints">Freehand polygon points (normalized 0-1).</param>
    /// <param name="freehandPathData">Serialized bezier path data (JSON bytes).</param>
    /// <param name="aiMaskData">AI RLE mask data (JSON bytes).</param>
    /// <returns>PNG image data as byte array. Empty array on failure.</returns>
    public static byte[] GenerateMaskImage(
        CropMode mode, int width, int height,
        Rect cropRect,
        Point circleCenter, double circleRadius,
        List<Point>? freehandPoints,
        byte[]? freehandPathData,
        byte[]? aiMaskData)
    {
        if (width <= 0 || height <= 0)
            return Array.Empty<byte>();

        try
        {
            using var bitmap = new Bitmap(width, height, PixelFormat.Format32bppArgb);
            using var graphics = Graphics.FromImage(bitmap);

            // High-quality rendering
            graphics.SmoothingMode = SmoothingMode.HighQuality;
            graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
            graphics.PixelOffsetMode = PixelOffsetMode.HighQuality;

            // Black background (masked out)
            graphics.Clear(Color.Black);

            // White brush for visible area
            using var whiteBrush = new SolidBrush(Color.White);

            switch (mode)
            {
                case CropMode.Rectangle:
                    RenderRectangleMask(graphics, whiteBrush, cropRect, width, height);
                    break;

                case CropMode.Circle:
                    RenderCircleMask(graphics, whiteBrush, circleCenter, circleRadius, width, height);
                    break;

                case CropMode.Freehand:
                    RenderFreehandMask(graphics, whiteBrush, freehandPoints, freehandPathData, width, height);
                    break;

                case CropMode.AI:
                    RenderAIMask(bitmap, graphics, aiMaskData, width, height);
                    break;
            }

            return BitmapToPng(bitmap);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[MaskRenderer] Failed to generate mask: {ex.Message}");
            return Array.Empty<byte>();
        }
    }

    #region Rectangle Mask

    private static void RenderRectangleMask(
        Graphics graphics, System.Drawing.Brush brush, Rect cropRect, int width, int height)
    {
        float x = (float)(cropRect.X * width);
        float y = (float)(cropRect.Y * height);
        float w = (float)(cropRect.Width * width);
        float h = (float)(cropRect.Height * height);

        graphics.FillRectangle(brush, x, y, w, h);
    }

    #endregion

    #region Circle Mask

    private static void RenderCircleMask(
        Graphics graphics, System.Drawing.Brush brush,
        Point center, double radius, int width, int height)
    {
        float cx = (float)(center.X * width);
        float cy = (float)(center.Y * height);
        float r = (float)(radius * Math.Min(width, height));

        graphics.FillEllipse(brush,
            cx - r, cy - r,
            r * 2, r * 2);
    }

    #endregion

    #region Freehand Mask

    private static void RenderFreehandMask(
        Graphics graphics, System.Drawing.Brush brush,
        List<Point>? points, byte[]? pathData,
        int width, int height)
    {
        // Try bezier path data first (higher quality)
        if (pathData != null && pathData.Length > 0)
        {
            try
            {
                string json = System.Text.Encoding.UTF8.GetString(pathData);
                var vertices = JsonSerializer.Deserialize<List<SerializedMaskVertex>>(json);

                if (vertices != null && vertices.Count >= 3)
                {
                    RenderBezierPath(graphics, brush, vertices, width, height);
                    return;
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"[MaskRenderer] Failed to parse bezier path data: {ex.Message}");
            }
        }

        // Fallback to simple polygon from points
        if (points == null || points.Count < 3)
            return;

        var polyPoints = points.Select(p =>
            new PointF((float)(p.X * width), (float)(p.Y * height))).ToArray();

        using var path = new GraphicsPath();
        path.AddPolygon(polyPoints);
        graphics.FillPath(brush, path);
    }

    /// <summary>
    /// Renders a bezier curve path from serialized mask vertices.
    /// Supports cubic bezier curves with control handles.
    /// </summary>
    private static void RenderBezierPath(
        Graphics graphics, System.Drawing.Brush brush,
        List<SerializedMaskVertex> vertices,
        int width, int height)
    {
        using var path = new GraphicsPath();

        var firstPos = ToPixel(vertices[0], width, height);
        path.StartFigure();

        for (int i = 0; i < vertices.Count; i++)
        {
            var from = vertices[i];
            var to = vertices[(i + 1) % vertices.Count];

            var fromPx = ToPixel(from, width, height);
            var toPx = ToPixel(to, width, height);

            bool hasFromHandle = from.controlOutX.HasValue && from.controlOutY.HasValue;
            bool hasToHandle = to.controlInX.HasValue && to.controlInY.HasValue;

            if (hasFromHandle && hasToHandle)
            {
                // Full cubic bezier
                var ctrl1 = new PointF(
                    (float)(fromPx.X + from.controlOutX!.Value * width),
                    (float)(fromPx.Y + from.controlOutY!.Value * height));
                var ctrl2 = new PointF(
                    (float)(toPx.X + to.controlInX!.Value * width),
                    (float)(toPx.Y + to.controlInY!.Value * height));

                path.AddBezier(fromPx, ctrl1, ctrl2, toPx);
            }
            else if (hasFromHandle)
            {
                // Quadratic approximation using cubic
                var ctrl = new PointF(
                    (float)(fromPx.X + from.controlOutX!.Value * width),
                    (float)(fromPx.Y + from.controlOutY!.Value * height));

                var ctrl1 = new PointF(
                    fromPx.X + 2f / 3f * (ctrl.X - fromPx.X),
                    fromPx.Y + 2f / 3f * (ctrl.Y - fromPx.Y));
                var ctrl2 = new PointF(
                    toPx.X + 2f / 3f * (ctrl.X - toPx.X),
                    toPx.Y + 2f / 3f * (ctrl.Y - toPx.Y));

                path.AddBezier(fromPx, ctrl1, ctrl2, toPx);
            }
            else if (hasToHandle)
            {
                var ctrl = new PointF(
                    (float)(toPx.X + to.controlInX!.Value * width),
                    (float)(toPx.Y + to.controlInY!.Value * height));

                var ctrl1 = new PointF(
                    fromPx.X + 2f / 3f * (ctrl.X - fromPx.X),
                    fromPx.Y + 2f / 3f * (ctrl.Y - fromPx.Y));
                var ctrl2 = new PointF(
                    toPx.X + 2f / 3f * (ctrl.X - toPx.X),
                    toPx.Y + 2f / 3f * (ctrl.Y - toPx.Y));

                path.AddBezier(fromPx, ctrl1, ctrl2, toPx);
            }
            else
            {
                path.AddLine(fromPx, toPx);
            }
        }

        path.CloseFigure();
        graphics.FillPath(brush, path);
    }

    private static PointF ToPixel(SerializedMaskVertex vertex, int width, int height)
    {
        return new PointF(
            (float)(vertex.positionX * width),
            (float)(vertex.positionY * height));
    }

    #endregion

    #region AI Mask

    /// <summary>
    /// Renders an AI mask from RLE-encoded data.
    /// Supports both fal.ai (row-major start/length pairs) and COCO (column-major alternating counts) formats.
    /// </summary>
    private static void RenderAIMask(
        Bitmap bitmap, Graphics graphics, byte[]? aiMaskData,
        int width, int height)
    {
        if (aiMaskData == null || aiMaskData.Length == 0)
        {
            // No mask data - fill white (show everything)
            graphics.Clear(Color.White);
            return;
        }

        try
        {
            string json = System.Text.Encoding.UTF8.GetString(aiMaskData);
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;

            // Get size
            int maskH = height, maskW = width;
            if (root.TryGetProperty("size", out var sizeArr) &&
                sizeArr.ValueKind == JsonValueKind.Array && sizeArr.GetArrayLength() >= 2)
            {
                maskH = sizeArr[0].GetInt32();
                maskW = sizeArr[1].GetInt32();
            }

            // Decode RLE counts to a bitmap
            byte[]? decodedMask = null;

            if (root.TryGetProperty("counts", out var counts))
            {
                if (counts.ValueKind == JsonValueKind.String)
                {
                    string countsStr = counts.GetString()!;

                    // Try fal.ai format first (space-separated start/length pairs)
                    decodedMask = TryDecodeFalAIRLE(countsStr, maskW, maskH);

                    // Fallback to COCO compressed RLE
                    decodedMask ??= TryDecodeCOCOCompressedRLE(countsStr, maskW, maskH);
                }
                else if (counts.ValueKind == JsonValueKind.Array)
                {
                    // COCO integer RLE
                    var intCounts = new List<int>();
                    foreach (var item in counts.EnumerateArray())
                        intCounts.Add(item.GetInt32());

                    decodedMask = DecodeCOCOIntegerRLE(intCounts, maskW, maskH);
                }
            }

            if (decodedMask == null)
            {
                Debug.WriteLine("[MaskRenderer] Failed to decode AI RLE mask");
                graphics.Clear(Color.White);
                return;
            }

            // Apply decoded mask to the bitmap
            ApplyMaskToBitmap(bitmap, decodedMask, maskW, maskH, width, height);
        }
        catch (Exception ex)
        {
            Debug.WriteLine($"[MaskRenderer] Failed to render AI mask: {ex.Message}");
            graphics.Clear(Color.White);
        }
    }

    /// <summary>
    /// Tries to decode fal.ai RLE format: space-separated (start, length) pairs in row-major order.
    /// </summary>
    private static byte[]? TryDecodeFalAIRLE(string rleString, int width, int height)
    {
        var parts = rleString.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length == 0 || parts.Length % 2 != 0)
            return null;

        var values = new int[parts.Length];
        for (int i = 0; i < parts.Length; i++)
        {
            if (!int.TryParse(parts[i], out values[i]))
                return null;
            if (values[i] < 0)
                return null; // fal.ai format doesn't have negatives
        }

        int totalPixels = width * height;
        var mask = new byte[totalPixels];

        for (int i = 0; i < values.Length; i += 2)
        {
            int start = values[i];
            int length = values[i + 1];

            for (int j = 0; j < length; j++)
            {
                int idx = start + j;
                if (idx >= 0 && idx < totalPixels)
                    mask[idx] = 255;
            }
        }

        return mask;
    }

    /// <summary>
    /// Tries to decode COCO compressed RLE format (LEB128-like with zigzag and delta encoding).
    /// </summary>
    private static byte[]? TryDecodeCOCOCompressedRLE(string rleString, int width, int height)
    {
        // COCO compressed uses ASCII chars starting at '0' (48)
        var validChars = "0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmno";
        if (!rleString.All(c => validChars.Contains(c)))
            return null;

        var counts = new List<int>();
        int i = 0;
        byte[] chars = System.Text.Encoding.ASCII.GetBytes(rleString);

        while (i < chars.Length)
        {
            int x = 0;
            int k = 0;
            bool more = true;

            while (more && i < chars.Length)
            {
                int c = chars[i] - 48;
                if (c < 0 || c > 63)
                    return null;

                x |= (c & 0x1f) << (5 * k);
                more = (c & 0x20) != 0;
                i++;
                k++;
            }

            // Zigzag decode
            if ((x & 1) != 0)
                x = -(x >> 1) - 1;
            else
                x = x >> 1;

            // Delta decode
            if (counts.Count == 0)
                counts.Add(x);
            else
                counts.Add(counts[^1] + x);
        }

        return DecodeCOCOIntegerRLE(counts, width, height);
    }

    /// <summary>
    /// Decodes standard COCO RLE with integer array counts (column-major order).
    /// Alternating: [bg_count, fg_count, bg_count, fg_count, ...]
    /// </summary>
    private static byte[] DecodeCOCOIntegerRLE(List<int> counts, int width, int height)
    {
        int totalPixels = width * height;
        var mask = new byte[totalPixels];

        int colMajorIdx = 0;
        byte value = 0; // Start with background

        foreach (int count in counts)
        {
            int safeCount = Math.Max(0, count);
            for (int j = 0; j < safeCount && colMajorIdx < totalPixels; j++)
            {
                // Column-major to row-major conversion
                int col = colMajorIdx / height;
                int row = colMajorIdx % height;
                int rowMajorIdx = row * width + col;

                if (rowMajorIdx >= 0 && rowMajorIdx < totalPixels)
                    mask[rowMajorIdx] = value;

                colMajorIdx++;
            }
            value = value == 0 ? (byte)255 : (byte)0;
        }

        return mask;
    }

    /// <summary>
    /// Applies a decoded mask array to a bitmap, with scaling if mask and bitmap dimensions differ.
    /// </summary>
    private static void ApplyMaskToBitmap(
        Bitmap bitmap, byte[] mask, int maskW, int maskH, int targetW, int targetH)
    {
        // Lock the bitmap for fast pixel manipulation
        var bmpData = bitmap.LockBits(
            new System.Drawing.Rectangle(0, 0, targetW, targetH),
            ImageLockMode.WriteOnly,
            PixelFormat.Format32bppArgb);

        try
        {
            unsafe
            {
                byte* ptr = (byte*)bmpData.Scan0;
                int stride = bmpData.Stride;

                for (int y = 0; y < targetH; y++)
                {
                    // Map target Y to mask Y
                    int maskY = (maskH == targetH) ? y : (int)((double)y / targetH * maskH);
                    maskY = Math.Clamp(maskY, 0, maskH - 1);

                    for (int x = 0; x < targetW; x++)
                    {
                        // Map target X to mask X
                        int maskX = (maskW == targetW) ? x : (int)((double)x / targetW * maskW);
                        maskX = Math.Clamp(maskX, 0, maskW - 1);

                        int maskIdx = maskY * maskW + maskX;
                        byte maskVal = maskIdx < mask.Length ? mask[maskIdx] : (byte)0;

                        int pixelOffset = y * stride + x * 4;
                        // BGRA format: set all channels to mask value
                        ptr[pixelOffset + 0] = maskVal; // B
                        ptr[pixelOffset + 1] = maskVal; // G
                        ptr[pixelOffset + 2] = maskVal; // R
                        ptr[pixelOffset + 3] = 255;     // A (fully opaque)
                    }
                }
            }
        }
        finally
        {
            bitmap.UnlockBits(bmpData);
        }
    }

    #endregion

    #region Helpers

    /// <summary>
    /// Converts a bitmap to PNG byte data.
    /// </summary>
    private static byte[] BitmapToPng(Bitmap bitmap)
    {
        using var stream = new MemoryStream();
        bitmap.Save(stream, ImageFormat.Png);
        return stream.ToArray();
    }

    #endregion
}
