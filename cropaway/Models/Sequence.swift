//
//  Sequence.swift
//  Cropaway
//
//  Represents a timeline/composition with clips.
//

import Foundation
import SwiftUI
import Combine

/// A timeline/composition containing video clips
@MainActor
final class Sequence: Identifiable, ObservableObject {
    // MARK: - Properties
    
    let id: UUID
    @Published var name: String
    let dateCreated: Date
    @Published var dateModified: Date
    
    // Timeline structure
    @Published var clips: [TimelineClip] = []
    
    // Sequence-level in/out marks (export range)
    @Published var inPoint: Double? = nil  // nil = sequence start
    @Published var outPoint: Double? = nil  // nil = sequence end
    
    // Sequence settings
    @Published var frameRate: Double = 30.0  // Target frame rate
    @Published var resolution: CGSize = .zero  // Target resolution (0 = auto from first clip)
    
    // MARK: - Computed Properties
    
    /// Total duration of the sequence (from start to last clip end)
    var duration: Double {
        guard let lastClip = clips.max(by: { $0.endTime < $1.endTime }) else {
            return 0
        }
        return lastClip.endTime
    }
    
    /// Export duration (respects in/out points if set)
    var exportDuration: Double {
        if let inPoint = inPoint, let outPoint = outPoint {
            return max(0, outPoint - inPoint)
        }
        return duration
    }
    
    /// Export start time (respects in point if set)
    var exportStartTime: Double {
        return inPoint ?? 0
    }
    
    /// Export end time (respects out point if set)
    var exportEndTime: Double {
        return outPoint ?? duration
    }
    
    // MARK: - Initialization
    
    init(name: String = "Untitled Sequence", id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.dateCreated = Date()
        self.dateModified = Date()
    }
    
    // MARK: - Clip Management
    
    /// Add a clip to the timeline
    func addClip(_ clip: TimelineClip) {
        clips.append(clip)
        sortClips()
        dateModified = Date()
    }
    
    /// Remove a clip from the timeline
    func removeClip(_ clip: TimelineClip) {
        clips.removeAll { $0.id == clip.id }
        dateModified = Date()
    }
    
    /// Remove clips by IDs
    func removeClips(withIds ids: Set<UUID>) {
        clips.removeAll { ids.contains($0.id) }
        dateModified = Date()
    }
    
    /// Get the clip at a specific sequence time
    func getClipAt(sequenceTime: Double) -> TimelineClip? {
        return clips.first { clip in
            sequenceTime >= clip.startTime && sequenceTime < clip.endTime
        }
    }
    
    /// Get all clips that overlap a time range
    func getClips(inRange range: ClosedRange<Double>) -> [TimelineClip] {
        return clips.filter { clip in
            // Clips overlap if: clip.start < range.end AND clip.end > range.start
            clip.startTime < range.upperBound && clip.endTime > range.lowerBound
        }
    }
    
    /// Check if a time range is free (no clips)
    func isTimeRangeFree(_ range: ClosedRange<Double>) -> Bool {
        return getClips(inRange: range).isEmpty
    }
    
    /// Sort clips by start time
    private func sortClips() {
        clips.sort { $0.startTime < $1.startTime }
    }
    
    // MARK: - Timeline Operations
    
    /// Move a clip to a new start time
    func moveClip(_ clip: TimelineClip, toTime newStartTime: Double) {
        guard let index = clips.firstIndex(where: { $0.id == clip.id }) else { return }
        clips[index].startTime = max(0, newStartTime)
        sortClips()
        dateModified = Date()
    }
    
    /// Ripple delete: remove clip and shift subsequent clips left
    func rippleDeleteClip(_ clip: TimelineClip) {
        let clipDuration = clip.duration
        let clipStartTime = clip.startTime
        
        // Remove the clip
        removeClip(clip)
        
        // Shift all clips that start after this clip
        for i in 0..<clips.count {
            if clips[i].startTime >= clipStartTime {
                clips[i].startTime -= clipDuration
            }
        }
        
        sortClips()
        dateModified = Date()
    }
    
    /// Insert a clip and ripple subsequent clips right
    func rippleInsertClip(_ clip: TimelineClip, atTime time: Double) {
        let insertTime = max(0, time)
        clip.startTime = insertTime
        
        // Shift all clips that start at or after insert time
        for i in 0..<clips.count {
            if clips[i].startTime >= insertTime {
                clips[i].startTime += clip.duration
            }
        }
        
        addClip(clip)
        dateModified = Date()
    }
}

// MARK: - Codable

extension Sequence {
    struct Snapshot: Codable {
        let id: UUID
        let name: String
        let dateCreated: Date
        let dateModified: Date
        let clipSnapshots: [TimelineClip.Snapshot]
        let inPoint: Double?
        let outPoint: Double?
        let frameRate: Double
        let resolution: CGSize
    }
    
    func snapshot(mediaAssets: [MediaAsset]) -> Snapshot {
        return Snapshot(
            id: id,
            name: name,
            dateCreated: dateCreated,
            dateModified: dateModified,
            clipSnapshots: clips.map { $0.snapshot() },
            inPoint: inPoint,
            outPoint: outPoint,
            frameRate: frameRate,
            resolution: resolution
        )
    }
    
    static func fromSnapshot(_ snapshot: Snapshot, mediaAssets: [MediaAsset]) -> Sequence {
        let sequence = Sequence(name: snapshot.name, id: snapshot.id)
        sequence.inPoint = snapshot.inPoint
        sequence.outPoint = snapshot.outPoint
        sequence.frameRate = snapshot.frameRate
        sequence.resolution = snapshot.resolution
        
        // Restore clips with resolved media asset references
        sequence.clips = snapshot.clipSnapshots.compactMap { clipSnapshot in
            TimelineClip.fromSnapshot(clipSnapshot, mediaAssets: mediaAssets)
        }
        
        return sequence
    }
}

// MARK: - Hashable & Equatable

extension Sequence: Hashable {
    static func == (lhs: Sequence, rhs: Sequence) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
