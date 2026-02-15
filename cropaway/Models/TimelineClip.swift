//
//  TimelineClip.swift
//  Cropaway
//
//  Represents an instance of a MediaAsset placed on a timeline with
//  independent trim points, position, and crop configuration.
//

import Foundation
import SwiftUI
import Combine

/// A clip instance on a timeline with trim points and crop settings
@MainActor
final class TimelineClip: Identifiable, ObservableObject {
    // MARK: - Properties
    
    let id: UUID
    
    // Reference to source media (strong reference for now)
    let mediaAsset: MediaAsset
    
    // Timeline placement (SEQUENCE time space)
    @Published var startTime: Double  // Position on timeline in seconds
    
    // Source trim (SOURCE time space)
    @Published var sourceInPoint: Double   // Where in source video to start (seconds)
    @Published var sourceOutPoint: Double  // Where in source video to end (seconds)
    
    // Per-clip crop configuration (keyframes stored in CLIP LOCAL time)
    @Published var cropConfiguration: CropConfiguration
    
    // Display properties
    @Published var name: String  // User-friendly clip name
    @Published var color: NSColor?  // Timeline color label
    
    // MARK: - Computed Properties
    
    /// Duration of the clip on the timeline (derived from trim points)
    var duration: Double {
        return sourceOutPoint - sourceInPoint
    }
    
    /// End time of the clip on the timeline
    var endTime: Double {
        return startTime + duration
    }
    
    // MARK: - Initialization
    
    init(mediaAsset: MediaAsset,
         startTime: Double,
         sourceInPoint: Double,
         sourceOutPoint: Double,
         id: UUID = UUID()) {
        self.id = id
        self.mediaAsset = mediaAsset
        self.startTime = max(0, startTime)
        self.sourceInPoint = max(0, sourceInPoint)
        self.sourceOutPoint = sourceOutPoint
        self.cropConfiguration = CropConfiguration()
        self.name = mediaAsset.fileName
        self.color = nil
        
        // Validate that sourceOutPoint > sourceInPoint
        if self.sourceOutPoint <= self.sourceInPoint {
            self.sourceOutPoint = self.sourceInPoint + 1.0  // Minimum 1 second
        }
    }
    
    // MARK: - Time Mapping Functions
    
    /// Maps sequence time to source video time
    /// - Parameter sequenceTime: Time on the timeline (sequence time domain)
    /// - Returns: Corresponding time in the source video file
    func sourceTime(fromSequenceTime sequenceTime: Double) -> Double {
        // Calculate offset within this clip
        let offsetInClip = sequenceTime - startTime
        
        // Add to source in point
        let sourceTime = sourceInPoint + offsetInClip
        
        // Clamp to source range
        return min(max(sourceTime, sourceInPoint), sourceOutPoint)
    }
    
    /// Maps source video time to sequence time
    /// - Parameter sourceTime: Time in the source video file
    /// - Returns: Corresponding time on the timeline (sequence time domain)
    func sequenceTime(fromSourceTime sourceTime: Double) -> Double {
        // Calculate offset from source in point
        let offsetInSource = sourceTime - sourceInPoint
        
        // Add to clip start time
        return startTime + offsetInSource
    }
    
    /// Maps sequence time to clip-local time (for keyframe interpolation)
    /// Clip-local time is always 0 at clip start, regardless of position on timeline
    /// - Parameter sequenceTime: Time on the timeline (sequence time domain)
    /// - Returns: Time relative to clip start (0 = clip start)
    func clipLocalTime(fromSequenceTime sequenceTime: Double) -> Double {
        return sequenceTime - startTime
    }
    
    /// Maps clip-local time to sequence time
    /// - Parameter localTime: Time relative to clip start (0 = clip start)
    /// - Returns: Corresponding time on the timeline (sequence time domain)
    func sequenceTime(fromClipLocalTime localTime: Double) -> Double {
        return startTime + localTime
    }
    
    /// Maps clip-local time to source time
    /// - Parameter localTime: Time relative to clip start (0 = clip start)
    /// - Returns: Corresponding time in the source video file
    func sourceTime(fromClipLocalTime localTime: Double) -> Double {
        return sourceInPoint + localTime
    }
    
    /// Maps source time to clip-local time
    /// - Parameter sourceTime: Time in the source video file
    /// - Returns: Time relative to clip start (0 = clip start)
    func clipLocalTime(fromSourceTime sourceTime: Double) -> Double {
        return sourceTime - sourceInPoint
    }
    
    /// Check if a sequence time falls within this clip's range
    /// - Parameter sequenceTime: Time on the timeline
    /// - Returns: True if the time is within [startTime, endTime)
    func contains(sequenceTime: Double) -> Bool {
        return sequenceTime >= startTime && sequenceTime < endTime
    }
    
    // MARK: - Trimming Operations
    
    /// Trim the start of the clip (adjusts sourceInPoint and startTime)
    /// - Parameter delta: Amount to trim (positive = trim more, negative = extend)
    func trimStart(by delta: Double) {
        let newSourceIn = sourceInPoint + delta
        
        // Ensure we don't trim past the source out point
        guard newSourceIn < sourceOutPoint else { return }
        
        // Ensure we don't go before source start
        guard newSourceIn >= 0 else { return }
        
        sourceInPoint = newSourceIn
    }
    
    /// Trim the end of the clip (adjusts sourceOutPoint)
    /// - Parameter delta: Amount to trim (positive = trim more, negative = extend)
    func trimEnd(by delta: Double) {
        let newSourceOut = sourceOutPoint - delta
        
        // Ensure we don't trim past the source in point
        guard newSourceOut > sourceInPoint else { return }
        
        // Ensure we don't go past source duration
        let maxSourceOut = mediaAsset.metadata.duration
        guard newSourceOut <= maxSourceOut else { return }
        
        sourceOutPoint = newSourceOut
    }
    
    /// Slip edit: adjust source in/out while maintaining clip duration and position
    /// - Parameter delta: Amount to slip (positive = later in source, negative = earlier)
    func slip(by delta: Double) {
        let newSourceIn = sourceInPoint + delta
        let newSourceOut = sourceOutPoint + delta
        
        // Check bounds
        guard newSourceIn >= 0 else { return }
        guard newSourceOut <= mediaAsset.metadata.duration else { return }
        
        sourceInPoint = newSourceIn
        sourceOutPoint = newSourceOut
    }
}

// MARK: - Codable

extension TimelineClip {
    struct Snapshot: Codable {
        let id: UUID
        let mediaAssetId: UUID
        let startTime: Double
        let sourceInPoint: Double
        let sourceOutPoint: Double
        let cropConfiguration: CropConfiguration
        let name: String
        let colorData: Data?
    }
    
    func snapshot() -> Snapshot {
        let colorData: Data?
        if let color = color {
            colorData = try? NSKeyedArchiver.archivedData(withRootObject: color, requiringSecureCoding: false)
        } else {
            colorData = nil
        }
        
        return Snapshot(
            id: id,
            mediaAssetId: mediaAsset.id,
            startTime: startTime,
            sourceInPoint: sourceInPoint,
            sourceOutPoint: sourceOutPoint,
            cropConfiguration: cropConfiguration,
            name: name,
            colorData: colorData
        )
    }
    
    static func fromSnapshot(_ snapshot: Snapshot, mediaAssets: [MediaAsset]) -> TimelineClip? {
        // Find the media asset
        guard let mediaAsset = mediaAssets.first(where: { $0.id == snapshot.mediaAssetId }) else {
            return nil
        }
        
        let clip = TimelineClip(
            mediaAsset: mediaAsset,
            startTime: snapshot.startTime,
            sourceInPoint: snapshot.sourceInPoint,
            sourceOutPoint: snapshot.sourceOutPoint,
            id: snapshot.id
        )
        
        clip.cropConfiguration = snapshot.cropConfiguration.copy()
        clip.name = snapshot.name
        
        if let colorData = snapshot.colorData {
            clip.color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData)
        }
        
        return clip
    }
}

// MARK: - Hashable & Equatable

extension TimelineClip: Hashable {
    static func == (lhs: TimelineClip, rhs: TimelineClip) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}


