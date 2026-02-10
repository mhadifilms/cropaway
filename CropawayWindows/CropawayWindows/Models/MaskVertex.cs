// MaskVertex.cs
// CropawayWindows

using System.Text.Json.Serialization;
using System.Windows;

namespace CropawayWindows.Models;

/// <summary>
/// A vertex in a freehand mask path that supports bezier curves.
/// All coordinates are normalized to the 0-1 range relative to video dimensions.
/// Control handles are stored relative to the vertex position.
/// </summary>
public sealed class MaskVertex : IEquatable<MaskVertex>
{
    /// <summary>
    /// Unique identifier for this vertex.
    /// </summary>
    public Guid Id { get; init; } = Guid.NewGuid();

    /// <summary>
    /// The vertex position in normalized 0-1 coordinates.
    /// </summary>
    public Point Position { get; set; }

    /// <summary>
    /// Incoming bezier control handle, relative to <see cref="Position"/>.
    /// Null indicates a sharp corner with no incoming curve.
    /// </summary>
    public Point? ControlIn { get; set; }

    /// <summary>
    /// Outgoing bezier control handle, relative to <see cref="Position"/>.
    /// Null indicates a sharp corner with no outgoing curve.
    /// </summary>
    public Point? ControlOut { get; set; }

    public MaskVertex()
    {
        Position = new Point(0, 0);
    }

    public MaskVertex(Point position, Point? controlIn = null, Point? controlOut = null)
    {
        Position = position;
        ControlIn = controlIn;
        ControlOut = controlOut;
    }

    /// <summary>
    /// Whether this vertex has any bezier curve handles.
    /// </summary>
    [JsonIgnore]
    public bool HasCurve => ControlIn.HasValue || ControlOut.HasValue;

    /// <summary>
    /// Gets the absolute position of the incoming control handle in normalized coordinates.
    /// Returns null if no incoming control handle is set.
    /// </summary>
    [JsonIgnore]
    public Point? AbsoluteControlIn =>
        ControlIn.HasValue
            ? new Point(Position.X + ControlIn.Value.X, Position.Y + ControlIn.Value.Y)
            : null;

    /// <summary>
    /// Gets the absolute position of the outgoing control handle in normalized coordinates.
    /// Returns null if no outgoing control handle is set.
    /// </summary>
    [JsonIgnore]
    public Point? AbsoluteControlOut =>
        ControlOut.HasValue
            ? new Point(Position.X + ControlOut.Value.X, Position.Y + ControlOut.Value.Y)
            : null;

    /// <summary>
    /// Mirrors the outgoing control handle to create the incoming handle (for smooth curves).
    /// </summary>
    public void MirrorControlIn()
    {
        if (ControlOut.HasValue)
        {
            ControlIn = new Point(-ControlOut.Value.X, -ControlOut.Value.Y);
        }
    }

    /// <summary>
    /// Mirrors the incoming control handle to create the outgoing handle (for smooth curves).
    /// </summary>
    public void MirrorControlOut()
    {
        if (ControlIn.HasValue)
        {
            ControlOut = new Point(-ControlIn.Value.X, -ControlIn.Value.Y);
        }
    }

    public bool Equals(MaskVertex? other)
    {
        if (other is null) return false;
        if (ReferenceEquals(this, other)) return true;
        return Id == other.Id;
    }

    public override bool Equals(object? obj) => Equals(obj as MaskVertex);

    public override int GetHashCode() => Id.GetHashCode();

    public override string ToString() =>
        $"MaskVertex({Position.X:F3},{Position.Y:F3}{(HasCurve ? " [curved]" : "")})";
}

/// <summary>
/// Extension methods for collections of <see cref="MaskVertex"/>.
/// </summary>
public static class MaskVertexCollectionExtensions
{
    /// <summary>
    /// Converts a list of mask vertices to simple points (loses bezier data).
    /// </summary>
    public static List<Point> ToPoints(this IEnumerable<MaskVertex> vertices) =>
        vertices.Select(v => v.Position).ToList();

    /// <summary>
    /// Creates mask vertices from simple points (no bezier data).
    /// </summary>
    public static List<MaskVertex> ToVertices(this IEnumerable<Point> points) =>
        points.Select(p => new MaskVertex(p)).ToList();
}
