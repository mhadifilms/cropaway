using System.Windows;

namespace CropawayWindows.Utilities;

/// <summary>
/// Geometry extension methods for normalized coordinate conversions.
/// Equivalent to macOS CGExtensions.swift with denormalized(to:) methods.
/// All crop coordinates are stored normalized (0-1) and converted to pixel at export time.
/// </summary>
public static class GeometryExtensions
{
    /// <summary>
    /// Convert a normalized (0-1) rectangle to pixel coordinates for the given dimensions.
    /// </summary>
    public static Rect Denormalize(this Rect normalized, double width, double height)
    {
        return new Rect(
            normalized.X * width,
            normalized.Y * height,
            normalized.Width * width,
            normalized.Height * height);
    }

    /// <summary>
    /// Convert a normalized (0-1) rectangle to pixel coordinates for the given size.
    /// </summary>
    public static Rect Denormalize(this Rect normalized, Size size)
    {
        return normalized.Denormalize(size.Width, size.Height);
    }

    /// <summary>
    /// Convert pixel coordinates to normalized (0-1) for the given dimensions.
    /// </summary>
    public static Rect Normalize(this Rect pixel, double width, double height)
    {
        if (width <= 0 || height <= 0) return new Rect(0, 0, 1, 1);
        return new Rect(
            pixel.X / width,
            pixel.Y / height,
            pixel.Width / width,
            pixel.Height / height);
    }

    /// <summary>
    /// Convert a normalized (0-1) point to pixel coordinates.
    /// </summary>
    public static Point Denormalize(this Point normalized, double width, double height)
    {
        return new Point(normalized.X * width, normalized.Y * height);
    }

    public static Point Denormalize(this Point normalized, Size size)
    {
        return normalized.Denormalize(size.Width, size.Height);
    }

    /// <summary>
    /// Convert pixel point to normalized (0-1) coordinates.
    /// </summary>
    public static Point Normalize(this Point pixel, double width, double height)
    {
        if (width <= 0 || height <= 0) return new Point(0.5, 0.5);
        return new Point(pixel.X / width, pixel.Y / height);
    }

    /// <summary>
    /// Linear interpolation between two doubles.
    /// </summary>
    public static double Lerp(double a, double b, double t)
    {
        return a + (b - a) * t;
    }

    /// <summary>
    /// Linear interpolation between two points.
    /// </summary>
    public static Point Lerp(Point a, Point b, double t)
    {
        return new Point(
            a.X + (b.X - a.X) * t,
            a.Y + (b.Y - a.Y) * t);
    }

    /// <summary>
    /// Linear interpolation between two rectangles.
    /// </summary>
    public static Rect Lerp(Rect a, Rect b, double t)
    {
        return new Rect(
            GeometryExtensions.Lerp(a.X, b.X, t),
            GeometryExtensions.Lerp(a.Y, b.Y, t),
            GeometryExtensions.Lerp(a.Width, b.Width, t),
            GeometryExtensions.Lerp(a.Height, b.Height, t));
    }

    /// <summary>
    /// Ensure dimensions are even (required for FFmpeg compatibility).
    /// </summary>
    public static int MakeEven(this int value)
    {
        return value % 2 == 0 ? value : Math.Max(2, value - 1);
    }

    /// <summary>
    /// Distance between two points.
    /// </summary>
    public static double DistanceTo(this Point a, Point b)
    {
        var dx = a.X - b.X;
        var dy = a.Y - b.Y;
        return Math.Sqrt(dx * dx + dy * dy);
    }

    /// <summary>
    /// Clamp a value to a range.
    /// </summary>
    public static double Clamp(this double value, double min, double max)
    {
        return Math.Max(min, Math.Min(max, value));
    }
}
