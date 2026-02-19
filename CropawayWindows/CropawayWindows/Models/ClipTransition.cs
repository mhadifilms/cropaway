// ClipTransition.cs
// CropawayWindows

using System.Text.Json.Serialization;
using CommunityToolkit.Mvvm.ComponentModel;

namespace CropawayWindows.Models;

/// <summary>
/// Represents a transition between two clips in a timeline sequence.
/// Indexed by the clip it follows (afterClipIndex). Duration is clamped
/// to the 0.1-2.0 second range.
/// </summary>
public partial class ClipTransition : ObservableObject, IEquatable<ClipTransition>
{
    /// <summary>
    /// Unique identifier for this transition.
    /// </summary>
    public Guid Id { get; init; } = Guid.NewGuid();

    /// <summary>
    /// Type of transition effect (Cut, Fade, or FadeToBlack).
    /// </summary>
    [ObservableProperty]
    private TransitionType _type = TransitionType.Cut;

    /// <summary>
    /// Duration of the transition in seconds. Clamped to the range 0.1-2.0.
    /// Ignored for Cut transitions (which are instantaneous).
    /// </summary>
    [ObservableProperty]
    private double _duration = 0.5;

    /// <summary>
    /// Index of the clip this transition follows. The transition occurs
    /// between clip[AfterClipIndex] and clip[AfterClipIndex + 1].
    /// </summary>
    public int AfterClipIndex { get; init; }

    public ClipTransition()
    {
    }

    public ClipTransition(TransitionType type, double duration, int afterClipIndex)
    {
        Type = type;
        _duration = Math.Clamp(duration, 0.1, 2.0);
        AfterClipIndex = afterClipIndex;
    }

    // -- Clamping on property change --

    partial void OnDurationChanged(double value)
    {
        double clamped = Math.Clamp(value, 0.1, 2.0);
        if (Math.Abs(clamped - value) > 0.0001)
        {
            Duration = clamped;
        }
    }

    // -- Computed properties --

    /// <summary>
    /// Effective duration of this transition. Returns 0 for Cut transitions
    /// (which are instantaneous) and the configured duration for all others.
    /// </summary>
    [JsonIgnore]
    public double EffectiveDuration =>
        Type.RequiresDuration() ? Duration : 0;

    /// <summary>
    /// Creates a copy of this transition with a different afterClipIndex.
    /// Used when clips are inserted, removed, or reordered in the timeline.
    /// </summary>
    public ClipTransition CopyWithNewIndex(int newIndex)
    {
        return new ClipTransition(Type, Duration, newIndex);
    }

    public bool Equals(ClipTransition? other)
    {
        if (other is null) return false;
        if (ReferenceEquals(this, other)) return true;
        return Id == other.Id;
    }

    public override bool Equals(object? obj) => Equals(obj as ClipTransition);

    public override int GetHashCode() => Id.GetHashCode();

    public static bool operator ==(ClipTransition? left, ClipTransition? right) =>
        left is null ? right is null : left.Equals(right);

    public static bool operator !=(ClipTransition? left, ClipTransition? right) =>
        !(left == right);

    public override string ToString() =>
        $"ClipTransition({Type.DisplayName()}, {Duration:F2}s, after clip {AfterClipIndex})";
}
