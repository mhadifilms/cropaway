//
//  Timeline.swift
//  cropaway
//

import Foundation
import Combine

/// Represents a sequence of video clips with transitions between them
final class Timeline: Identifiable, ObservableObject, Codable {
    let id: UUID

    /// Name of this timeline/sequence
    @Published var name: String

    /// Ordered list of clips in the timeline
    @Published var clips: [TimelineClip]

    /// Transitions between clips (indexed by afterClipIndex)
    @Published var transitions: [ClipTransition]

    /// Creation date
    let dateCreated: Date

    /// Last modified date
    @Published var dateModified: Date

    private var cancellables = Set<AnyCancellable>()

    init(
        id: UUID = UUID(),
        name: String = "Untitled Sequence",
        clips: [TimelineClip] = [],
        transitions: [ClipTransition] = []
    ) {
        self.id = id
        self.name = name
        self.clips = clips
        self.transitions = transitions
        self.dateCreated = Date()
        self.dateModified = Date()

        setupObservers()
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, name, clips, transitions, dateCreated, dateModified
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        clips = try container.decode([TimelineClip].self, forKey: .clips)
        transitions = try container.decode([ClipTransition].self, forKey: .transitions)
        dateCreated = try container.decode(Date.self, forKey: .dateCreated)
        dateModified = try container.decode(Date.self, forKey: .dateModified)

        setupObservers()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(clips, forKey: .clips)
        try container.encode(transitions, forKey: .transitions)
        try container.encode(dateCreated, forKey: .dateCreated)
        try container.encode(dateModified, forKey: .dateModified)
    }

    private func setupObservers() {
        // Mark as modified when clips or transitions change
        $clips.sink { [weak self] _ in
            self?.dateModified = Date()
        }.store(in: &cancellables)

        $transitions.sink { [weak self] _ in
            self?.dateModified = Date()
        }.store(in: &cancellables)
    }

    // MARK: - Computed Properties

    /// Total duration of the timeline in seconds
    var totalDuration: Double {
        let clipsDuration = clips.reduce(0) { $0 + $1.trimmedDuration }
        let transitionsDuration = transitions.reduce(0) { $0 + $1.effectiveDuration }
        // Transitions overlap clips, so subtract half the transition duration from each side
        let overlapAdjustment = transitionsDuration  // Each transition overlaps by its full duration
        let duration = max(0, clipsDuration - overlapAdjustment)
        
        // If duration is 0 or very small, return a minimum to ensure clips are visible
        // This can happen if metadata hasn't loaded yet
        return duration > 0.01 ? duration : Double(clips.count) * 1.0
    }

    /// Number of clips in the timeline
    var clipCount: Int {
        clips.count
    }

    /// Whether the timeline is empty
    var isEmpty: Bool {
        clips.isEmpty
    }

    /// Whether the timeline has multiple clips (can have transitions)
    var hasMultipleClips: Bool {
        clips.count > 1
    }

    // MARK: - Clip Management

    /// Add a clip to the end of the timeline
    func addClip(_ clip: TimelineClip) {
        clips.append(clip)
    }

    /// Add a clip from a video item
    func addClip(from videoItem: VideoItem) {
        let clip = TimelineClip(videoItem: videoItem)
        addClip(clip)
    }

    /// Insert a clip at a specific index
    func insertClip(_ clip: TimelineClip, at index: Int) {
        let safeIndex = max(0, min(clips.count, index))

        // Update transition indices for clips after the insertion point
        for transition in transitions where transition.afterClipIndex >= safeIndex {
            // Create new transition with updated index since afterClipIndex is let
            if let idx = transitions.firstIndex(where: { $0.id == transition.id }) {
                transitions[idx] = transition.copy(withNewIndex: transition.afterClipIndex + 1)
            }
        }

        clips.insert(clip, at: safeIndex)
    }

    /// Remove a clip at a specific index
    func removeClip(at index: Int) {
        guard index >= 0 && index < clips.count else { return }

        // Remove transitions that reference this clip
        transitions.removeAll { $0.afterClipIndex == index }

        // Update indices for transitions after this clip
        for (idx, transition) in transitions.enumerated() where transition.afterClipIndex > index {
            transitions[idx] = transition.copy(withNewIndex: transition.afterClipIndex - 1)
        }

        clips.remove(at: index)
    }

    /// Remove a specific clip
    func removeClip(_ clip: TimelineClip) {
        if let index = clips.firstIndex(where: { $0.id == clip.id }) {
            removeClip(at: index)
        }
    }

    /// Move a clip from one index to another
    func moveClip(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0 && sourceIndex < clips.count,
              destinationIndex >= 0 && destinationIndex <= clips.count,
              sourceIndex != destinationIndex else { return }

        let clip = clips.remove(at: sourceIndex)

        // Adjust destination if moving forward
        let adjustedDestination = destinationIndex > sourceIndex ? destinationIndex - 1 : destinationIndex
        clips.insert(clip, at: adjustedDestination)

        // Update transition indices to match new clip positions
        // This requires careful index tracking without rebuilding all transitions
        updateTransitionIndicesAfterMove(from: sourceIndex, to: adjustedDestination)
    }

    /// Split a clip at a specific time within the clip
    func splitClip(at clipIndex: Int, atTime timeInClip: Double) -> Bool {
        guard clipIndex >= 0 && clipIndex < clips.count else { return false }

        let clip = clips[clipIndex]
        guard let newClip = clip.split(at: timeInClip / clip.trimmedDuration) else {
            return false
        }

        // Insert new clip after the current one
        insertClip(newClip, at: clipIndex + 1)
        return true
    }

    // MARK: - Transition Management

    /// Get the transition after a specific clip index
    func transition(afterClipIndex index: Int) -> ClipTransition? {
        transitions.first { $0.afterClipIndex == index }
    }

    /// Set the transition type after a specific clip
    func setTransitionType(afterClipIndex index: Int, type: TransitionType) {
        if let transition = transition(afterClipIndex: index) {
            transition.type = type
        }
    }

    /// Set the transition duration after a specific clip
    func setTransitionDuration(afterClipIndex index: Int, duration: Double) {
        if let transition = transition(afterClipIndex: index) {
            transition.duration = max(0.1, min(2.0, duration))
        }
    }

    /// Rebuild all transitions with default cut type
    private func updateTransitionIndicesAfterMove(from sourceIndex: Int, to destinationIndex: Int) {
        // When a clip moves, transitions need to update their indices
        // This is complex but avoids auto-creating transitions
        
        var updatedTransitions: [ClipTransition] = []
        
        for transition in transitions {
            var newIndex = transition.afterClipIndex
            
            // If transition is attached to the moved clip
            if transition.afterClipIndex == sourceIndex {
                newIndex = destinationIndex
            }
            // If transition is between source and destination
            else if sourceIndex < destinationIndex {
                // Moving forward: indices in between shift down
                if transition.afterClipIndex > sourceIndex && transition.afterClipIndex <= destinationIndex {
                    newIndex = transition.afterClipIndex - 1
                }
            } else {
                // Moving backward: indices in between shift up
                if transition.afterClipIndex >= destinationIndex && transition.afterClipIndex < sourceIndex {
                    newIndex = transition.afterClipIndex + 1
                }
            }
            
            updatedTransitions.append(transition.copy(withNewIndex: newIndex))
        }
        
        transitions = updatedTransitions
    }

    // MARK: - Time Calculations

    /// Get the clip at a specific timeline time
    func clip(at timelineTime: Double) -> (clip: TimelineClip, clipIndex: Int, timeInClip: Double)? {
        var currentTime: Double = 0

        for (index, clip) in clips.enumerated() {
            let clipDuration = clip.trimmedDuration

            // Account for transition overlap ONLY if transition exists
            if index > 0, let prevTransition = transition(afterClipIndex: index - 1) {
                let overlap = prevTransition.effectiveDuration / 2
                currentTime -= overlap
            }

            let clipEndTime = currentTime + clipDuration

            if timelineTime >= currentTime && timelineTime < clipEndTime {
                let timeInClip = timelineTime - currentTime
                return (clip, index, timeInClip)
            }

            currentTime = clipEndTime
            
            // Add gap if no transition to next clip
            if index < clips.count - 1, transition(afterClipIndex: index) == nil {
                currentTime += 0.02 // 2pt gap in time units
            }
        }

        // Return last clip if time is past the end
        if let lastClip = clips.last {
            return (lastClip, clips.count - 1, lastClip.trimmedDuration)
        }

        return nil
    }

    /// Get the start time of a clip in the timeline
    func startTime(forClipAt index: Int) -> Double {
        var time: Double = 0
        for i in 0..<index {
            time += clips[i].trimmedDuration
            if let transition = transition(afterClipIndex: i) {
                time -= transition.effectiveDuration
            } else {
                // Add gap if no transition exists
                time += 0.02
            }
        }
        return time
    }

    // MARK: - Resolution After Load

    /// Resolve all clip video item references after loading from persistence
    func resolveVideoItems(from videos: [VideoItem]) {
        for clip in clips {
            clip.resolveVideoItem(from: videos)
        }
    }
}

// MARK: - Equatable

extension Timeline: Equatable {
    static func == (lhs: Timeline, rhs: Timeline) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Hashable

extension Timeline: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
