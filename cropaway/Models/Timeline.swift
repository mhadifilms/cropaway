//
//  Timeline.swift
//  cropaway
//

import Foundation
import CoreGraphics
import Combine

/// Represents a sequence of video clips with transitions between them
final class Timeline: Identifiable, ObservableObject, Codable {
    let id: UUID

    /// Name of this timeline/sequence
    @Published var name: String

    /// Tracks in the timeline (NEW: multi-track support)
    @Published var tracks: [Track]

    /// Ordered list of clips in the timeline (DEPRECATED: kept for backward compatibility)
    @Published var clips: [TimelineClip]

    /// Transitions between clips (indexed by afterClipIndex)
    @Published var transitions: [ClipTransition]

    /// In point for export range (nil = start of timeline)
    @Published var inPoint: Double?

    /// Out point for export range (nil = end of timeline)
    @Published var outPoint: Double?

    /// Timeline frame rate (default: 30fps)
    @Published var frameRate: Double

    /// Timeline resolution (default: .zero uses first clip's resolution)
    @Published var resolution: CGSize

    /// Creation date
    let dateCreated: Date

    /// Last modified date
    @Published var dateModified: Date

    private var cancellables = Set<AnyCancellable>()

    init(
        id: UUID = UUID(),
        name: String = "Untitled Sequence",
        tracks: [Track] = [],
        clips: [TimelineClip] = [],
        transitions: [ClipTransition] = [],
        inPoint: Double? = nil,
        outPoint: Double? = nil,
        frameRate: Double = 30.0,
        resolution: CGSize = .zero
    ) {
        self.id = id
        self.name = name
        self.tracks = tracks
        self.clips = clips
        self.transitions = transitions
        self.inPoint = inPoint
        self.outPoint = outPoint
        self.frameRate = frameRate
        self.resolution = resolution
        self.dateCreated = Date()
        self.dateModified = Date()

        setupObservers()
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, name, tracks, clips, transitions, dateCreated, dateModified
        case inPoint, outPoint, frameRate, resolution
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        
        // Try to decode tracks first (new format)
        tracks = try container.decodeIfPresent([Track].self, forKey: .tracks) ?? []
        
        // Decode clips (kept for backward compatibility)
        clips = try container.decode([TimelineClip].self, forKey: .clips)
        
        transitions = try container.decode([ClipTransition].self, forKey: .transitions)
        dateCreated = try container.decode(Date.self, forKey: .dateCreated)
        dateModified = try container.decode(Date.self, forKey: .dateModified)
        
        // New properties with defaults for backward compatibility
        inPoint = try container.decodeIfPresent(Double.self, forKey: .inPoint)
        outPoint = try container.decodeIfPresent(Double.self, forKey: .outPoint)
        frameRate = try container.decodeIfPresent(Double.self, forKey: .frameRate) ?? 30.0
        
        // Decode resolution if present
        if let width = try? container.decodeIfPresent(Double.self, forKey: .resolution),
           let height = try? container.decodeIfPresent(Double.self, forKey: .resolution) {
            resolution = CGSize(width: width, height: height)
        } else {
            resolution = .zero
        }

        setupObservers()
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(tracks, forKey: .tracks)
        try container.encode(clips, forKey: .clips)
        try container.encode(transitions, forKey: .transitions)
        try container.encode(dateCreated, forKey: .dateCreated)
        try container.encode(dateModified, forKey: .dateModified)
        try container.encodeIfPresent(inPoint, forKey: .inPoint)
        try container.encodeIfPresent(outPoint, forKey: .outPoint)
        try container.encode(frameRate, forKey: .frameRate)
        
        // Encode resolution as width/height
        if resolution != .zero {
            try container.encode(resolution.width, forKey: .resolution)
            try container.encode(resolution.height, forKey: .resolution)
        }
    }

    private func setupObservers() {
        // Mark as modified when tracks, clips or transitions change
        $tracks.sink { [weak self] _ in
            self?.dateModified = Date()
        }.store(in: &cancellables)
        
        $clips.sink { [weak self] _ in
            self?.dateModified = Date()
        }.store(in: &cancellables)

        $transitions.sink { [weak self] _ in
            self?.dateModified = Date()
        }.store(in: &cancellables)
        
        $inPoint.sink { [weak self] _ in
            self?.dateModified = Date()
        }.store(in: &cancellables)
        
        $outPoint.sink { [weak self] _ in
            self?.dateModified = Date()
        }.store(in: &cancellables)
    }

    // MARK: - Computed Properties

    /// Total duration of the timeline in seconds
    var totalDuration: Double {
        // For a simple concatenated timeline without transition overlap,
        // duration is simply the sum of all clip durations
        let clipsDuration = clips.reduce(0.0) { $0 + $1.trimmedDuration }

        // If we have transitions in the future that actually overlap,
        // we'll need to account for them. For now, transitions are
        // just markers and don't affect playback duration.
        // let overlapDuration = transitions.reduce(0.0) { $0 + $1.effectiveDuration }

        // Return clips duration, or minimum of 0.01 if no clips
        return max(0.01, clipsDuration)
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
    
    // MARK: - Multi-Track Computed Properties
    
    /// All clips across all tracks (for unified access)
    var allClips: [TimelineClip] {
        tracks.flatMap { $0.clips }
    }
    
    /// Video tracks only, sorted by vertical order (top to bottom)
    var videoTracks: [Track] {
        tracks
            .filter { $0.mediaType == .video }
            .sorted { $0.verticalOrder > $1.verticalOrder }
    }
    
    /// Audio tracks only
    var audioTracks: [Track] {
        tracks
            .filter { $0.mediaType == .audio }
            .sorted { $0.verticalOrder > $1.verticalOrder }
    }
    
    /// Find a clip by ID across all tracks
    func findClip(withID id: UUID) -> TimelineClip? {
        for track in tracks {
            if let clip = track.clips.first(where: { $0.id == id }) {
                return clip
            }
        }
        return nil
    }
    
    /// Find track and index for a clip by ID
    func findClipLocation(withID id: UUID) -> (track: Track, clipIndex: Int)? {
        for track in tracks {
            if let index = track.clips.firstIndex(where: { $0.id == id }) {
                return (track, index)
            }
        }
        return nil
    }
    
    /// Export duration (respects in/out points)
    var exportDuration: Double {
        if let inPt = inPoint, let outPt = outPoint {
            return max(0, outPt - inPt)
        }
        return totalDuration
    }
    
    /// Whether in/out points are set
    var hasInOutPoints: Bool {
        inPoint != nil && outPoint != nil
    }
    
    // MARK: - Track Management
    
    /// Add a new track to the timeline
    func addTrack(_ track: Track) {
        tracks.append(track)
    }
    
    /// Create and add a new video track
    @discardableResult
    func createVideoTrack(name: String? = nil) -> Track {
        let trackNumber = videoTracks.count + 1
        let track = Track(
            name: name ?? "Video \(trackNumber)",
            mediaType: .video,
            verticalOrder: tracks.count
        )
        addTrack(track)
        return track
    }
    
    /// Create and add a new audio track
    @discardableResult
    func createAudioTrack(name: String? = nil) -> Track {
        let trackNumber = audioTracks.count + 1
        let track = Track(
            name: name ?? "Audio \(trackNumber)",
            mediaType: .audio,
            verticalOrder: tracks.count
        )
        addTrack(track)
        return track
    }
    
    /// Remove a track by ID
    @discardableResult
    func removeTrack(_ trackID: UUID) -> Track? {
        guard let index = tracks.firstIndex(where: { $0.id == trackID }) else { return nil }
        return tracks.remove(at: index)
    }
    
    /// Find a track by ID
    func track(withID id: UUID) -> Track? {
        tracks.first { $0.id == id }
    }
    
    /// Find the track containing a specific clip
    func track(containing clipID: UUID) -> Track? {
        tracks.first { track in
            track.clips.contains { $0.id == clipID }
        }
    }
    
    /// Move a track to a new vertical order position
    func moveTrack(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0, sourceIndex < tracks.count,
              destinationIndex >= 0, destinationIndex < tracks.count else { return }
        let track = tracks.remove(at: sourceIndex)
        tracks.insert(track, at: destinationIndex)
        
        // Update vertical order for all tracks
        for (index, track) in tracks.enumerated() {
            track.verticalOrder = index
        }
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
        // Resolve clips in deprecated clips array
        for clip in clips {
            clip.resolveVideoItem(from: videos)
        }
        
        // Resolve clips in all tracks
        for track in tracks {
            for clip in track.clips {
                clip.resolveVideoItem(from: videos)
            }
        }
    }
    
    // MARK: - Helper Methods

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
