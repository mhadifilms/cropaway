//
//  TimelineClip.swift
//  cropaway
//

import Foundation
import Combine
import AppKit

/// Represents a single video clip in a timeline sequence
/// References an existing VideoItem but adds trim points and timeline position
final class TimelineClip: Identifiable, ObservableObject, Codable {
    let id: UUID

    /// Reference to the source video item
    /// Note: Not encoded - resolved via sourceVideoID on load
    weak var videoItem: VideoItem?

    /// ID of the source video for persistence
    let sourceVideoID: UUID

    /// In point as normalized value (0-1) relative to source duration
    @Published var inPoint: Double {
        didSet {
            inPoint = max(0, min(outPoint - 0.01, inPoint))
        }
    }

    /// Out point as normalized value (0-1) relative to source duration
    @Published var outPoint: Double {
        didSet {
            outPoint = max(inPoint + 0.01, min(1.0, outPoint))
        }
    }

    /// Cached thumbnail for display in timeline track
    @Published var thumbnail: NSImage?
    
    private var cancellables = Set<AnyCancellable>()

    init(
        id: UUID = UUID(),
        videoItem: VideoItem,
        inPoint: Double = 0.0,
        outPoint: Double = 1.0
    ) {
        self.id = id
        self.videoItem = videoItem
        self.sourceVideoID = videoItem.id
        self.inPoint = max(0, min(1.0, inPoint))
        self.outPoint = max(0, min(1.0, outPoint))
        self.thumbnail = videoItem.thumbnail
        
        // Observe thumbnail changes from the video item
        videoItem.$thumbnail
            .sink { [weak self] newThumbnail in
                self?.thumbnail = newThumbnail
            }
            .store(in: &cancellables)
        
        // Observe metadata changes to trigger duration recalculation
        videoItem.$metadata
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, sourceVideoID, inPoint, outPoint
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sourceVideoID = try container.decode(UUID.self, forKey: .sourceVideoID)
        inPoint = try container.decode(Double.self, forKey: .inPoint)
        outPoint = try container.decode(Double.self, forKey: .outPoint)
        // videoItem and thumbnail will be resolved after loading
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sourceVideoID, forKey: .sourceVideoID)
        try container.encode(inPoint, forKey: .inPoint)
        try container.encode(outPoint, forKey: .outPoint)
    }

    // MARK: - Computed Properties

    /// Duration of the source video in seconds
    var sourceDuration: Double {
        videoItem?.metadata.duration ?? 0
    }

    /// Trimmed duration of this clip in seconds
    var trimmedDuration: Double {
        (outPoint - inPoint) * sourceDuration
    }

    /// Start time in source video (seconds)
    var sourceStartTime: Double {
        inPoint * sourceDuration
    }

    /// End time in source video (seconds)
    var sourceEndTime: Double {
        outPoint * sourceDuration
    }

    /// Display name for the clip
    var displayName: String {
        videoItem?.fileName ?? "Unknown"
    }

    /// Whether the clip has been trimmed from its original duration
    var isTrimmed: Bool {
        inPoint > 0.001 || outPoint < 0.999
    }

    /// Crop configuration from the source video
    var cropConfiguration: CropConfiguration? {
        videoItem?.cropConfiguration
    }

    // MARK: - Methods

    /// Resolve the video item reference after loading from persistence
    func resolveVideoItem(from videos: [VideoItem]) {
        videoItem = videos.first { $0.id == sourceVideoID }
        thumbnail = videoItem?.thumbnail
        
        // Re-subscribe to thumbnail and metadata changes
        if let videoItem = videoItem {
            cancellables.removeAll()
            videoItem.$thumbnail
                .sink { [weak self] newThumbnail in
                    self?.thumbnail = newThumbnail
                }
                .store(in: &cancellables)
            
            videoItem.$metadata
                .sink { [weak self] _ in
                    self?.objectWillChange.send()
                }
                .store(in: &cancellables)
        }
    }

    /// Set in point from a time in seconds
    func setInPointFromTime(_ time: Double) {
        guard sourceDuration > 0 else { return }
        inPoint = time / sourceDuration
    }

    /// Set out point from a time in seconds
    func setOutPointFromTime(_ time: Double) {
        guard sourceDuration > 0 else { return }
        outPoint = time / sourceDuration
    }

    /// Split this clip at a normalized position (0-1 within trimmed region)
    /// Returns the new clip that comes after this one
    func split(at normalizedPosition: Double) -> TimelineClip? {
        guard let video = videoItem else { return nil }

        // Convert position within trimmed region to position in source
        let splitPointInSource = inPoint + normalizedPosition * (outPoint - inPoint)

        // Validate split point
        guard splitPointInSource > inPoint + 0.01 && splitPointInSource < outPoint - 0.01 else {
            return nil
        }

        // Create new clip for the second half
        let newClip = TimelineClip(
            videoItem: video,
            inPoint: splitPointInSource,
            outPoint: outPoint
        )

        // Adjust this clip's out point
        outPoint = splitPointInSource

        return newClip
    }

    /// Create a copy of this clip
    func copy() -> TimelineClip? {
        guard let video = videoItem else { return nil }
        return TimelineClip(
            videoItem: video,
            inPoint: inPoint,
            outPoint: outPoint
        )
    }
}

// MARK: - Equatable

extension TimelineClip: Equatable {
    static func == (lhs: TimelineClip, rhs: TimelineClip) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - Hashable

extension TimelineClip: Hashable {
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
