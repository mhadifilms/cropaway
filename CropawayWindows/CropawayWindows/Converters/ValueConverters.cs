using System.Globalization;
using System.Windows;
using System.Windows.Data;

namespace CropawayWindows.Converters;

/// <summary>
/// Converts a boolean to Visibility (true = Visible, false = Collapsed).
/// </summary>
public class BoolToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is bool b)
            return b ? Visibility.Visible : Visibility.Collapsed;
        return Visibility.Collapsed;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        return value is Visibility v && v == Visibility.Visible;
    }
}

/// <summary>
/// Converts null to Visible (shows placeholder when value is null), non-null to Collapsed.
/// </summary>
public class NullToVisibilityConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object parameter, CultureInfo culture)
    {
        return value == null ? Visibility.Visible : Visibility.Collapsed;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        throw new NotSupportedException();
    }
}

/// <summary>
/// Converts an enum value to boolean based on parameter matching.
/// Used for ToggleButton IsChecked binding to enum properties.
/// </summary>
public class EnumToBoolConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value == null || parameter == null) return false;
        var enumStr = parameter.ToString();
        return value.ToString() == enumStr;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is bool b && b && parameter != null)
        {
            return Enum.Parse(targetType, parameter.ToString()!);
        }
        return Binding.DoNothing;
    }
}

/// <summary>
/// Inverts a boolean value.
/// </summary>
public class InverseBoolConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        return value is bool b && !b;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        return value is bool b && !b;
    }
}

/// <summary>
/// Converts a double (0-1) progress value to a percentage string.
/// </summary>
public class ProgressToPercentConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is double d)
            return $"{d:P0}";
        return "0%";
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        throw new NotSupportedException();
    }
}

/// <summary>
/// Converts duration in seconds to a display string (e.g., "1:23").
/// </summary>
public class DurationToStringConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is double seconds && seconds > 0)
        {
            var ts = TimeSpan.FromSeconds(seconds);
            if (ts.Hours > 0)
                return ts.ToString(@"h\:mm\:ss");
            return ts.ToString(@"m\:ss");
        }
        return "0:00";
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        throw new NotSupportedException();
    }
}

/// <summary>
/// Converts video metadata to a summary string.
/// </summary>
public class MetadataToSummaryConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is Models.VideoMetadata meta)
        {
            var parts = new List<string>();
            if (meta.Width > 0 && meta.Height > 0)
                parts.Add($"{meta.Width}x{meta.Height}");
            if (!string.IsNullOrEmpty(meta.CodecType))
                parts.Add(meta.CodecType);
            if (meta.FrameRate > 0)
                parts.Add($"{meta.FrameRate:F1}fps");
            return string.Join(" · ", parts);
        }
        return "";
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        throw new NotSupportedException();
    }
}

/// <summary>
/// Multi-value converter for slider fill width calculation.
/// </summary>
public class SliderFillWidthConverter : IMultiValueConverter
{
    public object Convert(object[] values, Type targetType, object parameter, CultureInfo culture)
    {
        if (values.Length >= 2 && values[0] is double val && values[1] is double width)
        {
            return val * width;
        }
        return 0.0;
    }

    public object[] ConvertBack(object value, Type[] targetTypes, object parameter, CultureInfo culture)
    {
        throw new NotSupportedException();
    }
}

/// <summary>
/// Returns "s" for pluralization when count != 1, empty string when count is 1.
/// </summary>
public class PluralSuffixConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is int count)
            return count == 1 ? "" : "s";
        return "s";
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        throw new NotSupportedException();
    }
}

/// <summary>
/// Converts zero count to Visible, non-zero to Collapsed. Used for empty state overlays.
/// </summary>
public class ZeroToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is int count)
            return count == 0 ? Visibility.Visible : Visibility.Collapsed;
        return Visibility.Collapsed;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        throw new NotSupportedException();
    }
}

/// <summary>
/// Converts non-null value to true, null to false. Used for IsEnabled bindings.
/// </summary>
public class NotNullToBoolConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object parameter, CultureInfo culture)
    {
        return value != null;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        throw new NotSupportedException();
    }
}

/// <summary>
/// Converts non-null to Visible, null to Collapsed. Inverse of NullToVisibilityConverter.
/// </summary>
public class NotNullToVisibilityConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object parameter, CultureInfo culture)
    {
        return value != null ? Visibility.Visible : Visibility.Collapsed;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        throw new NotSupportedException();
    }
}

/// <summary>
/// Converts a boolean to inverse Visibility (true = Collapsed, false = Visible).
/// </summary>
public class InverseBoolToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is bool b)
            return b ? Visibility.Collapsed : Visibility.Visible;
        return Visibility.Visible;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        return value is Visibility v && v == Visibility.Collapsed;
    }
}

/// <summary>
/// Converts non-empty string to Visible, empty/null string to Collapsed.
/// </summary>
public class StringToVisibilityConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is string s && !string.IsNullOrWhiteSpace(s))
            return Visibility.Visible;
        return Visibility.Collapsed;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        throw new NotSupportedException();
    }
}

/// <summary>
/// Converts a CropMode enum to a user-friendly display string for the status bar.
/// Rectangle -> "Rectangle", Circle -> "Circle", Freehand -> "Mask", AI -> "AI"
/// </summary>
public class CropModeToDisplayConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is Models.CropMode mode)
        {
            return mode switch
            {
                Models.CropMode.Rectangle => "Rectangle",
                Models.CropMode.Circle => "Circle",
                Models.CropMode.Freehand => "Mask",
                Models.CropMode.AI => "AI",
                _ => "Rectangle"
            };
        }
        return "Rectangle";
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        throw new NotSupportedException();
    }
}

/// <summary>
/// Converts a codec type string (e.g., "h264", "hevc", "prores") to a friendly display name.
/// </summary>
public class CodecTypeToDisplayConverter : IValueConverter
{
    public object Convert(object? value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is string codec && !string.IsNullOrEmpty(codec))
        {
            return codec.ToLowerInvariant() switch
            {
                "h264" => "H.264",
                "avc" => "H.264",
                "hevc" => "H.265",
                "h265" => "H.265",
                "prores" => "ProRes",
                "vp9" => "VP9",
                "vp8" => "VP8",
                "av1" => "AV1",
                "mpeg4" => "MPEG-4",
                "mpeg2video" => "MPEG-2",
                "dnxhd" => "DNxHD",
                "dnxhr" => "DNxHR",
                "mjpeg" => "MJPEG",
                _ => codec.ToUpperInvariant()
            };
        }
        return "";
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        throw new NotSupportedException();
    }
}

/// <summary>
/// Converts a frame rate double to a display string. Shows up to 3 decimal places
/// for common non-integer frame rates (23.976, 29.97, 59.94), otherwise 2 decimals.
/// Trims trailing zeros for clean display.
/// </summary>
public class FrameRateToDisplayConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is double fps && fps > 0)
        {
            // Common non-integer frame rates get 3 decimal places
            string formatted;
            double fractional = fps - Math.Floor(fps);
            if (fractional > 0.001 && fractional < 0.999)
                formatted = fps.ToString("F3").TrimEnd('0').TrimEnd('.');
            else
                formatted = ((int)Math.Round(fps)).ToString();

            return $"{formatted} fps";
        }
        return "";
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        throw new NotSupportedException();
    }
}

/// <summary>
/// Converts a boolean HDR flag to Visibility. True = Visible, False = Collapsed.
/// Same as BoolToVisibilityConverter but semantically clearer for HDR badge usage.
/// </summary>
public class HdrToVisibilityConverter : IValueConverter
{
    public object Convert(object value, Type targetType, object parameter, CultureInfo culture)
    {
        if (value is bool isHdr)
            return isHdr ? Visibility.Visible : Visibility.Collapsed;
        return Visibility.Collapsed;
    }

    public object ConvertBack(object value, Type targetType, object parameter, CultureInfo culture)
    {
        throw new NotSupportedException();
    }
}

/// <summary>
/// Multi-value converter that formats current playback position and total duration
/// as "MM:SS / MM:SS" or "H:MM:SS / H:MM:SS" for the status bar.
/// Values[0] = CurrentTime (double, seconds), Values[1] = Duration (double, seconds).
/// </summary>
public class PlaybackPositionConverter : IMultiValueConverter
{
    public object Convert(object[] values, Type targetType, object parameter, CultureInfo culture)
    {
        if (values.Length >= 2 &&
            values[0] is double currentTime &&
            values[1] is double duration)
        {
            return $"{FormatTime(currentTime)} / {FormatTime(duration)}";
        }
        return "00:00 / 00:00";
    }

    private static string FormatTime(double seconds)
    {
        if (seconds < 0) seconds = 0;
        var ts = TimeSpan.FromSeconds(seconds);
        if (ts.TotalHours >= 1)
            return ts.ToString(@"h\:mm\:ss");
        return ts.ToString(@"mm\:ss");
    }

    public object[] ConvertBack(object value, Type[] targetTypes, object parameter, CultureInfo culture)
    {
        throw new NotSupportedException();
    }
}
