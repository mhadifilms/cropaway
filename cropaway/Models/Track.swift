//
//  Track.swift
//  cropaway
//
//  Created by Claude Code
//

import Foundation
import SwiftUI

/// Media type for a track
enum TrackMediaType: String, Codable, Sendable {
    case video
    case audio
}

/// Blend mode for video track compositing
enum BlendMode: String, Codable, Sendable {
    case normal
    case multiply
    case screen
    case overlay
    case darken
    case lighten
    case colorDodge
    case colorBurn
    case softLight
    case hardLight
    case difference
    case exclusion
}

/// A track in a timeline containing an ordered list of clips
@Observable
final class Track: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String
    var clips: [TimelineClip]
    var mediaType: TrackMediaType
    var isLocked: Bool
    var isMuted: Bool
    var isHidden: Bool
    var verticalOrder: Int
    var opacity: Double
    var blendMode: BlendMode
    
    /// PHASE 10: Adjustable track height
    var height: CGFloat
    
    // MARK: - Initialization
    
    init(
        id: UUID = UUID(),
        name: String,
        clips: [TimelineClip] = [],
        mediaType: TrackMediaType = .video,
        isLocked: Bool = false,
        isMuted: Bool = false,
        isHidden: Bool = false,
        verticalOrder: Int = 0,
        opacity: Double = 1.0,
        blendMode: BlendMode = .normal,
        height: CGFloat? = nil
    ) {
        self.id = id
        self.name = name
        self.clips = clips
        self.mediaType = mediaType
        self.isLocked = isLocked
        self.isMuted = isMuted
        self.isHidden = isHidden
        self.verticalOrder = verticalOrder
        self.opacity = opacity
        self.blendMode = blendMode
        self.height = height ?? (mediaType == .video ? 80 : 50)
    }
    
    // MARK: - Codable
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case clips
        case mediaType
        case isLocked
        case isMuted
        case isHidden
        case verticalOrder
        case opacity
        case blendMode
        case height  // PHASE 10
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        clips = try container.decode([TimelineClip].self, forKey: .clips)
        mediaType = try container.decode(TrackMediaType.self, forKey: .mediaType)
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        isHidden = try container.decodeIfPresent(Bool.self, forKey: .isHidden) ?? false
        verticalOrder = try container.decodeIfPresent(Int.self, forKey: .verticalOrder) ?? 0
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0
        blendMode = try container.decodeIfPresent(BlendMode.self, forKey: .blendMode) ?? .normal
        
        // PHASE 10: Decode height with default based on media type
        let decodedMediaType = try container.decode(TrackMediaType.self, forKey: .mediaType)
        height = try container.decodeIfPresent(CGFloat.self, forKey: .height) ?? (decodedMediaType == .video ? 80 : 50)
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(clips, forKey: .clips)
        try container.encode(mediaType, forKey: .mediaType)
        try container.encode(isLocked, forKey: .isLocked)
        try container.encode(isMuted, forKey: .isMuted)
        try container.encode(isHidden, forKey: .isHidden)
        try container.encode(verticalOrder, forKey: .verticalOrder)
        try container.encode(opacity, forKey: .opacity)
        try container.encode(blendMode, forKey: .blendMode)
        try container.encode(height, forKey: .height)  // PHASE 10
    }
    
    // MARK: - Computed Properties
    
    /// Total duration of all clips in this track
    var duration: Double {
        clips.reduce(0) { $0 + $1.trimmedDuration }
    }
    
    /// Whether this track is a video track
    var isVideoTrack: Bool {
        mediaType == .video
    }
    
    /// Whether this track is an audio track
    var isAudioTrack: Bool {
        mediaType == .audio
    }
    
    // MARK: - Clip Management
    
    /// Add a clip to the end of the track
    func addClip(_ clip: TimelineClip) {
        clips.append(clip)
    }
    
    /// Insert a clip at a specific index
    func insertClip(_ clip: TimelineClip, at index: Int) {
        guard index >= 0, index <= clips.count else { return }
        clips.insert(clip, at: index)
    }
    
    /// Remove a clip by ID
    @discardableResult
    func removeClip(_ clipID: UUID) -> TimelineClip? {
        guard let index = clips.firstIndex(where: { $0.id == clipID }) else { return nil }
        return clips.remove(at: index)
    }
    
    /// Move a clip from one index to another
    func moveClip(from sourceIndex: Int, to destinationIndex: Int) {
        guard sourceIndex >= 0, sourceIndex < clips.count,
              destinationIndex >= 0, destinationIndex < clips.count else { return }
        let clip = clips.remove(at: sourceIndex)
        clips.insert(clip, at: destinationIndex)
    }
    
    /// Find a clip by ID
    func clip(withID id: UUID) -> TimelineClip? {
        clips.first { $0.id == id }
    }
    
    /// Find a clip at a specific timeline time
    func clip(at time: Double) -> (clip: TimelineClip, timeInClip: Double)? {
        var currentTime: Double = 0
        
        for clip in clips {
            let clipDuration = clip.trimmedDuration
            if time >= currentTime && time < currentTime + clipDuration {
                let timeInClip = time - currentTime
                return (clip, timeInClip)
            }
            currentTime += clipDuration
        }
        
        return nil
    }
    
    // MARK: - Track State
    
    /// Toggle track lock state
    func toggleLock() {
        isLocked.toggle()
    }
    
    /// Toggle track mute state (audio tracks only)
    func toggleMute() {
        guard isAudioTrack else { return }
        isMuted.toggle()
    }
    
    /// Toggle track visibility (video tracks only)
    func toggleVisibility() {
        guard isVideoTrack else { return }
        isHidden.toggle()
    }
}

// MARK: - Equatable

extension Track: Equatable {
    static func == (lhs: Track, rhs: Track) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Hashable

extension Track: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
