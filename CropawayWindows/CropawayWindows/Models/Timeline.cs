// Timeline.cs
// CropawayWindows

using System.Collections.ObjectModel;
using System.Text.Json.Serialization;
using CommunityToolkit.Mvvm.ComponentModel;

namespace CropawayWindows.Models;

/// <summary>
/// Represents a sequence of video clips with transitions between them.
/// Manages clip ordering, insertion, removal, movement, splitting, and
/// transition management. Maintains computed properties for total duration
/// and clip count.
/// </summary>
public partial class Timeline : ObservableObject, IEquatable<Timeline>
{
    /// <summary>
    /// Unique identifier for this timeline.
    /// </summary>
    public Guid Id { get; init; } = Guid.NewGuid();

    /// <summary>
    /// Display name for this timeline/sequence.
    /// </summary>
    [ObservableProperty]
    private string _name = "Untitled Sequence";

    /// <summary>
    /// Ordered list of clips in the timeline.
    /// </summary>
    [ObservableProperty]
    private ObservableCollection<TimelineClip> _clips = [];

    /// <summary>
    /// Transitions between clips, indexed by <see cref="ClipTransition.AfterClipIndex"/>.
    /// </summary>
    [ObservableProperty]
    private ObservableCollection<ClipTransition> _transitions = [];

    /// <summary>
    /// Date this timeline was created.
    /// </summary>
    public DateTime DateCreated { get; init; } = DateTime.Now;

    /// <summary>
    /// Date this timeline was last modified.
    /// </summary>
    [ObservableProperty]
    private DateTime _dateModified = DateTime.Now;

    public Timeline()
    {
    }

    public Timeline(string name, IEnumerable<TimelineClip>? clips = null)
    {
        Name = name;
        if (clips is not null)
        {
            _clips = new ObservableCollection<TimelineClip>(clips);
        }
    }

    // -- Computed properties --

    /// <summary>
    /// Total duration of the timeline in seconds. Sum of all trimmed clip durations.
    /// Returns a minimum of 0.01 to avoid zero-duration timelines.
    /// </summary>
    [JsonIgnore]
    public double TotalDuration
    {
        get
        {
            double clipsDuration = Clips.Sum(c => c.TrimmedDuration);
            return Math.Max(0.01, clipsDuration);
        }
    }

    /// <summary>
    /// Number of clips currently in the timeline.
    /// </summary>
    [JsonIgnore]
    public int ClipCount => Clips.Count;

    /// <summary>
    /// Whether the timeline contains no clips.
    /// </summary>
    [JsonIgnore]
    public bool IsEmpty => Clips.Count == 0;

    /// <summary>
    /// Whether the timeline has multiple clips (enabling transitions).
    /// </summary>
    [JsonIgnore]
    public bool HasMultipleClips => Clips.Count > 1;

    // -- Clip management --

    /// <summary>
    /// Adds a clip to the end of the timeline.
    /// </summary>
    public void AddClip(TimelineClip clip)
    {
        Clips.Add(clip);
        MarkModified();
    }

    /// <summary>
    /// Creates and adds a clip from a <see cref="VideoItem"/> to the end of the timeline.
    /// </summary>
    public void AddClip(VideoItem videoItem)
    {
        var clip = new TimelineClip(videoItem);
        AddClip(clip);
    }

    /// <summary>
    /// Inserts a clip at a specific index. Adjusts transition indices for clips
    /// after the insertion point.
    /// </summary>
    public void InsertClip(TimelineClip clip, int index)
    {
        int safeIndex = Math.Clamp(index, 0, Clips.Count);

        // Update transition indices for clips at or after the insertion point
        var updatedTransitions = Transitions
            .Select(t => t.AfterClipIndex >= safeIndex
                ? t.CopyWithNewIndex(t.AfterClipIndex + 1)
                : t)
            .ToList();

        Transitions = new ObservableCollection<ClipTransition>(updatedTransitions);
        Clips.Insert(safeIndex, clip);
        MarkModified();
    }

    /// <summary>
    /// Removes a clip at a specific index. Removes any transitions referencing
    /// this clip and adjusts indices for subsequent transitions.
    /// </summary>
    public void RemoveClip(int index)
    {
        if (index < 0 || index >= Clips.Count) return;

        // Remove transitions referencing this clip, adjust indices for later clips
        var updatedTransitions = Transitions
            .Where(t => t.AfterClipIndex != index)
            .Select(t => t.AfterClipIndex > index
                ? t.CopyWithNewIndex(t.AfterClipIndex - 1)
                : t)
            .ToList();

        Transitions = new ObservableCollection<ClipTransition>(updatedTransitions);
        Clips.RemoveAt(index);
        MarkModified();
    }

    /// <summary>
    /// Removes a specific clip from the timeline by finding its index.
    /// </summary>
    public void RemoveClip(TimelineClip clip)
    {
        int index = -1;
        for (int i = 0; i < Clips.Count; i++)
        {
            if (Clips[i].Id == clip.Id)
            {
                index = i;
                break;
            }
        }

        if (index >= 0)
        {
            RemoveClip(index);
        }
    }

    /// <summary>
    /// Moves a clip from one index to another, updating transition indices accordingly.
    /// </summary>
    public void MoveClip(int sourceIndex, int destinationIndex)
    {
        if (sourceIndex < 0 || sourceIndex >= Clips.Count ||
            destinationIndex < 0 || destinationIndex > Clips.Count ||
            sourceIndex == destinationIndex)
            return;

        var clip = Clips[sourceIndex];
        Clips.RemoveAt(sourceIndex);

        int adjustedDestination = destinationIndex > sourceIndex
            ? destinationIndex - 1
            : destinationIndex;

        Clips.Insert(adjustedDestination, clip);

        // Update transition indices
        UpdateTransitionIndicesAfterMove(sourceIndex, adjustedDestination);
        MarkModified();
    }

    /// <summary>
    /// Splits a clip at a specific time (in seconds) within the clip's trimmed duration.
    /// Returns true if the split was successful.
    /// </summary>
    public bool SplitClip(int clipIndex, double timeInClip)
    {
        if (clipIndex < 0 || clipIndex >= Clips.Count) return false;

        var clip = Clips[clipIndex];
        double normalizedPosition = clip.TrimmedDuration > 0
            ? timeInClip / clip.TrimmedDuration
            : 0.5;

        var newClip = clip.Split(normalizedPosition);
        if (newClip is null) return false;

        InsertClip(newClip, clipIndex + 1);
        return true;
    }

    // -- Transition management --

    /// <summary>
    /// Gets the transition after a specific clip index, if one exists.
    /// </summary>
    public ClipTransition? GetTransition(int afterClipIndex) =>
        Transitions.FirstOrDefault(t => t.AfterClipIndex == afterClipIndex);

    /// <summary>
    /// Sets the transition type after a specific clip.
    /// </summary>
    public void SetTransitionType(int afterClipIndex, TransitionType type)
    {
        var transition = GetTransition(afterClipIndex);
        if (transition is not null)
        {
            transition.Type = type;
            MarkModified();
        }
    }

    /// <summary>
    /// Sets the transition duration after a specific clip.
    /// </summary>
    public void SetTransitionDuration(int afterClipIndex, double duration)
    {
        var transition = GetTransition(afterClipIndex);
        if (transition is not null)
        {
            transition.Duration = Math.Clamp(duration, 0.1, 2.0);
            MarkModified();
        }
    }

    // -- Time calculations --

    /// <summary>
    /// Gets the clip at a specific timeline time, along with the clip index
    /// and the time offset within that clip.
    /// </summary>
    public (TimelineClip Clip, int ClipIndex, double TimeInClip)? GetClipAtTime(double timelineTime)
    {
        double currentTime = 0;

        for (int i = 0; i < Clips.Count; i++)
        {
            var clip = Clips[i];
            double clipDuration = clip.TrimmedDuration;

            // Account for transition overlap if a transition exists before this clip
            if (i > 0)
            {
                var prevTransition = GetTransition(i - 1);
                if (prevTransition is not null)
                {
                    currentTime -= prevTransition.EffectiveDuration / 2;
                }
            }

            double clipEndTime = currentTime + clipDuration;

            if (timelineTime >= currentTime && timelineTime < clipEndTime)
            {
                return (clip, i, timelineTime - currentTime);
            }

            currentTime = clipEndTime;

            // Add gap if no transition to next clip
            if (i < Clips.Count - 1 && GetTransition(i) is null)
            {
                currentTime += 0.02;
            }
        }

        // Return last clip if time is past the end
        if (Clips.Count > 0)
        {
            var lastClip = Clips[^1];
            return (lastClip, Clips.Count - 1, lastClip.TrimmedDuration);
        }

        return null;
    }

    /// <summary>
    /// Gets the start time of a clip (by index) within the overall timeline.
    /// </summary>
    public double GetClipStartTime(int clipIndex)
    {
        double time = 0;
        for (int i = 0; i < clipIndex && i < Clips.Count; i++)
        {
            time += Clips[i].TrimmedDuration;

            var transition = GetTransition(i);
            if (transition is not null)
            {
                time -= transition.EffectiveDuration;
            }
            else
            {
                time += 0.02; // Gap when no transition
            }
        }
        return time;
    }

    // -- Resolution after load --

    /// <summary>
    /// Resolves all clip video item references after loading from persistence.
    /// </summary>
    public void ResolveVideoItems(IEnumerable<VideoItem> videos)
    {
        var videoList = videos.ToList();
        foreach (var clip in Clips)
        {
            clip.ResolveVideoItem(videoList);
        }
    }

    // -- Private helpers --

    private void UpdateTransitionIndicesAfterMove(int sourceIndex, int destinationIndex)
    {
        var updatedTransitions = new List<ClipTransition>();

        foreach (var transition in Transitions)
        {
            int newIndex = transition.AfterClipIndex;

            if (transition.AfterClipIndex == sourceIndex)
            {
                newIndex = destinationIndex;
            }
            else if (sourceIndex < destinationIndex)
            {
                // Moving forward: indices between shift down
                if (transition.AfterClipIndex > sourceIndex &&
                    transition.AfterClipIndex <= destinationIndex)
                {
                    newIndex = transition.AfterClipIndex - 1;
                }
            }
            else
            {
                // Moving backward: indices between shift up
                if (transition.AfterClipIndex >= destinationIndex &&
                    transition.AfterClipIndex < sourceIndex)
                {
                    newIndex = transition.AfterClipIndex + 1;
                }
            }

            updatedTransitions.Add(transition.CopyWithNewIndex(newIndex));
        }

        Transitions = new ObservableCollection<ClipTransition>(updatedTransitions);
    }

    private void MarkModified()
    {
        DateModified = DateTime.Now;
    }

    public bool Equals(Timeline? other)
    {
        if (other is null) return false;
        if (ReferenceEquals(this, other)) return true;
        return Id == other.Id;
    }

    public override bool Equals(object? obj) => Equals(obj as Timeline);

    public override int GetHashCode() => Id.GetHashCode();

    public static bool operator ==(Timeline? left, Timeline? right) =>
        left is null ? right is null : left.Equals(right);

    public static bool operator !=(Timeline? left, Timeline? right) =>
        !(left == right);

    public override string ToString() =>
        $"Timeline({Name}, {ClipCount} clips, {TotalDuration:F2}s)";
}
