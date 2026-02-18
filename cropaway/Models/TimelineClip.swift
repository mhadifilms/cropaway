//
//  TimelineClip.swift
//  cropaway
//

import Foundation
import Combine
import AppKit
import AVFoundation

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
            // Clamp to valid range, avoiding recursion
            let clamped = max(0, min(outPoint - 0.01, inPoint))
            if abs(clamped - inPoint) > 0.0001 {
                inPoint = clamped
                return // Exit early, didSet will be called again with clamped value
            }
            // Only generate thumbnails if value actually changed
            if abs(oldValue - inPoint) > 0.0001 {
                debouncedGenerateThumbnailStrip()
            }
        }
    }

    /// Out point as normalized value (0-1) relative to source duration
    @Published var outPoint: Double {
        didSet {
            // Clamp to valid range, avoiding recursion
            let clamped = max(inPoint + 0.01, min(1.0, outPoint))
            if abs(clamped - outPoint) > 0.0001 {
                outPoint = clamped
                return // Exit early, didSet will be called again with clamped value
            }
            // Only generate thumbnails if value actually changed
            if abs(oldValue - outPoint) > 0.0001 {
                debouncedGenerateThumbnailStrip()
            }
        }
    }

    /// Cached thumbnail for display in timeline track
    @Published var thumbnail: NSImage?
    
    /// Strip of thumbnails for filmstrip display in timeline
    @Published var thumbnailStrip: [NSImage] = []
    
    /// Per-clip crop configuration (independent of source video)
    @Published var cropConfiguration: CropConfiguration?
    
    /// Per-clip transform properties
    @Published var scale: CGFloat = 1.0
    @Published var positionX: Double = 0.5  // normalized 0-1
    @Published var positionY: Double = 0.5  // normalized 0-1
    @Published var rotation: Double = 0.0   // degrees
    @Published var flipHorizontal: Bool = false
    @Published var flipVertical: Bool = false
    @Published var opacity: Double = 1.0
    
    /// PHASE 9: Per-clip audio properties
    @Published var volume: Float = 1.0  // 0.0 to 2.0 (0% to 200%)
    @Published var isMuted: Bool = false
    
    /// PHASE 9: Cached audio waveform samples
    @Published var audioWaveform: [Float] = []
    
    /// PHASE 10: Clip color label for organization
    @Published var colorLabel: ClipColorLabel = .none
    
    private var cancellables = Set<AnyCancellable>()
    
    /// Debounce thumbnail regeneration to prevent overwhelming during trim
    private var thumbnailGenerationTask: Task<Void, Never>?

    init(
        id: UUID = UUID(),
        videoItem: VideoItem,
        inPoint: Double = 0.0,
        outPoint: Double = 1.0,
        cropConfiguration: CropConfiguration? = nil
    ) {
        self.id = id
        self.videoItem = videoItem
        self.sourceVideoID = videoItem.id
        self.inPoint = max(0, min(1.0, inPoint))
        self.outPoint = max(0, min(1.0, outPoint))
        self.thumbnail = videoItem.thumbnail
        
        // Clone crop configuration from video if not provided
        if let providedConfig = cropConfiguration {
            self.cropConfiguration = providedConfig
        } else {
            self.cropConfiguration = CropConfiguration(from: videoItem.cropConfiguration)
        }
        
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
        
        // Generate thumbnail strip asynchronously
        Task {
            await generateThumbnailStrip()
        }
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id, sourceVideoID, inPoint, outPoint
        case cropConfiguration
        case scale, positionX, positionY, rotation
        case flipHorizontal, flipVertical, opacity
        case volume, isMuted  // PHASE 9: Audio properties
        case colorLabel  // PHASE 10: Clip color label
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sourceVideoID = try container.decode(UUID.self, forKey: .sourceVideoID)
        inPoint = try container.decode(Double.self, forKey: .inPoint)
        outPoint = try container.decode(Double.self, forKey: .outPoint)
        
        // Per-clip crop configuration will be created after resolving video item
        cropConfiguration = nil
        
        // Decode transform properties with defaults
        scale = try container.decodeIfPresent(CGFloat.self, forKey: .scale) ?? 1.0
        positionX = try container.decodeIfPresent(Double.self, forKey: .positionX) ?? 0.5
        positionY = try container.decodeIfPresent(Double.self, forKey: .positionY) ?? 0.5
        rotation = try container.decodeIfPresent(Double.self, forKey: .rotation) ?? 0.0
        flipHorizontal = try container.decodeIfPresent(Bool.self, forKey: .flipHorizontal) ?? false
        flipVertical = try container.decodeIfPresent(Bool.self, forKey: .flipVertical) ?? false
        opacity = try container.decodeIfPresent(Double.self, forKey: .opacity) ?? 1.0
        
        // PHASE 9: Decode audio properties with defaults
        volume = try container.decodeIfPresent(Float.self, forKey: .volume) ?? 1.0
        isMuted = try container.decodeIfPresent(Bool.self, forKey: .isMuted) ?? false
        
        // PHASE 10: Decode color label with default
        colorLabel = try container.decodeIfPresent(ClipColorLabel.self, forKey: .colorLabel) ?? .none
        
        // videoItem and thumbnail will be resolved after loading
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(sourceVideoID, forKey: .sourceVideoID)
        try container.encode(inPoint, forKey: .inPoint)
        try container.encode(outPoint, forKey: .outPoint)
        
        // Note: Crop configuration is not encoded here - it will be handled by migration
        // when loading from the old format
        
        // Encode transform properties (only if non-default)
        if scale != 1.0 {
            try container.encode(scale, forKey: .scale)
        }
        if positionX != 0.5 {
            try container.encode(positionX, forKey: .positionX)
        }
        if positionY != 0.5 {
            try container.encode(positionY, forKey: .positionY)
        }
        if rotation != 0.0 {
            try container.encode(rotation, forKey: .rotation)
        }
        if flipHorizontal {
            try container.encode(flipHorizontal, forKey: .flipHorizontal)
        }
        if flipVertical {
            try container.encode(flipVertical, forKey: .flipVertical)
        }
        if opacity != 1.0 {
            try container.encode(opacity, forKey: .opacity)
        }
        
        // PHASE 9: Encode audio properties (only if non-default)
        if volume != 1.0 {
            try container.encode(volume, forKey: .volume)
        }
        if isMuted {
            try container.encode(isMuted, forKey: .isMuted)
        }
        
        // PHASE 10: Encode color label (only if non-default)
        if colorLabel != .none {
            try container.encode(colorLabel, forKey: .colorLabel)
        }
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
    
    /// Whether this clip has transform modifications applied
    var hasTransforms: Bool {
        scale != 1.0 || positionX != 0.5 || positionY != 0.5 || rotation != 0.0 ||
        flipHorizontal || flipVertical || opacity != 1.0
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
    
    /// Debounced thumbnail strip generation to prevent overwhelming during trim operations
    private func debouncedGenerateThumbnailStrip() {
        // Cancel any pending thumbnail generation
        thumbnailGenerationTask?.cancel()
        
        // Schedule new generation with 150ms delay for snappy response
        // Safe now: using cached asset + fixed recursion bug
        thumbnailGenerationTask = Task {
            try? await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds
            
            // Check if task was cancelled
            guard !Task.isCancelled else { return }
            
            await generateThumbnailStrip()
        }
    }
    
    /// Generate a strip of thumbnails for filmstrip display
    /// - Parameter count: Number of thumbnails to generate (default 5)
    func generateThumbnailStrip(count: Int = 5) async {
        guard let video = videoItem, sourceDuration > 0 else { return }
        
        // Check for cancellation before starting
        guard !Task.isCancelled else { return }
        
        // PHASE 10: Use thumbnail cache for performance
        let cache = ThumbnailCacheService.shared
        let thumbnailSize = CGSize(width: 120, height: 80)
        
        var thumbs: [NSImage] = []
        let step = count > 1 ? (outPoint - inPoint) / Double(count - 1) : 0
        
        for i in 0..<count {
            // Check for cancellation on each iteration
            guard !Task.isCancelled else { return }
            
            let normalized = inPoint + step * Double(i)
            let timeInSeconds = normalized * sourceDuration
            
            do {
                let image = try await cache.getThumbnail(
                    for: video.sourceURL,
                    at: timeInSeconds,
                    size: thumbnailSize
                )
                thumbs.append(image)
            } catch {
                // If thumbnail generation fails or task cancelled, skip this frame
                if Task.isCancelled { return }
                continue
            }
        }
        
        // Final cancellation check before updating UI
        guard !Task.isCancelled else { return }
        
        await MainActor.run {
            self.thumbnailStrip = thumbs
        }
    }
    
    // PHASE 9: Generate audio waveform for this clip
    func generateAudioWaveform(sampleCount: Int = 100) async {
        guard let video = videoItem else { return }
        
        do {
            let asset = video.getAsset()
            let samples = try await AudioWaveformGenerator.generateWaveform(from: asset, sampleCount: sampleCount)
            
            await MainActor.run {
                self.audioWaveform = samples
            }
        } catch {
            print("Failed to generate waveform: \(error)")
        }
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
