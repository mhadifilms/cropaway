//
//  SequencePlayerViewModel.swift
//  Cropaway
//
//  Manages playback of sequences using AVComposition for seamless clip-to-clip transitions.
//

import Foundation
import SwiftUI
import AVFoundation
import Combine

@MainActor
final class SequencePlayerViewModel: ObservableObject {
    // MARK: - Published Properties
    
    @Published var player: AVPlayer?
    @Published var currentTime: Double = 0  // SEQUENCE time
    @Published var duration: Double = 0     // Sequence duration
    @Published var isPlaying: Bool = false
    @Published var currentClip: TimelineClip?
    @Published var currentClipCrop: InterpolatedCropState?
    @Published var currentRate: Float = 1.0
    
    // MARK: - Private Properties
    
    private var sequence: Sequence?
    private var composition: AVComposition?
    private var timeObserver: Any?
    private var timeObserverPlayer: AVPlayer?  // Keep reference for cleanup
    private var statusObserver: AnyCancellable?
    private var playerItemObserver: AnyCancellable?
    private var rebuildTask: Task<Void, Never>?
    private var isRebuildingComposition = false
    
    // Shuttle control state for J/K/L speed ramping
    private var shuttleSpeed: Float = 0
    private static let shuttleSpeeds: [Float] = [0.5, 1.0, 2.0, 4.0, 8.0]
    
    // Debouncing for composition rebuild
    private var rebuildDebounceTimer: Timer?
    
    // MARK: - Initialization
    
    init() {
        setupPlayer()
    }
    
    deinit {
        // Clean up observers
        if let observer = timeObserver, let player = timeObserverPlayer {
            player.removeTimeObserver(observer)
        }
        statusObserver?.cancel()
        playerItemObserver?.cancel()
        rebuildTask?.cancel()
        rebuildDebounceTimer?.invalidate()
    }
    
    // MARK: - Sequence Loading
    
    func loadSequence(_ sequence: Sequence) {
        self.sequence = sequence
        self.duration = sequence.duration
        
        // Rebuild composition for this sequence
        rebuildComposition()
    }
    
    func unloadSequence() {
        removeTimeObserver()
        player?.replaceCurrentItem(with: nil)
        sequence = nil
        composition = nil
        currentTime = 0
        duration = 0
        currentClip = nil
        currentClipCrop = nil
    }
    
    // MARK: - Composition Building
    
    /// Rebuild the AVComposition from the current sequence
    /// This creates a seamless timeline from all clips
    private func rebuildComposition() {
        guard sequence != nil else { return }
        
        // Cancel any existing rebuild
        rebuildTask?.cancel()
        
        // Debounce rapid rebuilds
        rebuildDebounceTimer?.invalidate()
        rebuildDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.performCompositionRebuild()
            }
        }
    }
    
    private func performCompositionRebuild() {
        guard let sequence = sequence else { return }
        
        isRebuildingComposition = true
        
        rebuildTask = Task { @MainActor in
            do {
                let composition = try await buildComposition(from: sequence)
                self.composition = composition
                
                // Create player item from composition
                let playerItem = AVPlayerItem(asset: composition)
                
                // Replace current item
                if let player = player {
                    player.replaceCurrentItem(with: playerItem)
                } else {
                    let newPlayer = AVPlayer(playerItem: playerItem)
                    self.player = newPlayer
                    setupPlayerObservers()
                }
                
                setupTimeObserver()
                isRebuildingComposition = false
            } catch {
                print("Failed to build composition: \(error)")
                isRebuildingComposition = false
            }
        }
    }
    
    /// Build AVComposition from sequence clips
    private func buildComposition(from sequence: Sequence) async throws -> AVComposition {
        let composition = AVMutableComposition()
        
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw NSError(domain: "SequencePlayer", code: 1, 
                         userInfo: [NSLocalizedDescriptionKey: "Failed to create video track"])
        }
        
        guard let audioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw NSError(domain: "SequencePlayer", code: 2,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to create audio track"])
        }
        
        // Insert each clip at its timeline position
        for clip in sequence.clips {
            let sourceAsset = clip.mediaAsset.getAsset()
            
            // Load source tracks
            let sourceTracks = try await sourceAsset.loadTracks(withMediaType: .video)
            guard let sourceVideoTrack = sourceTracks.first else {
                continue
            }
            
            // Define source time range (trimmed portion)
            let sourceTimeRange = CMTimeRange(
                start: CMTime(seconds: clip.sourceInPoint, preferredTimescale: 600),
                duration: CMTime(seconds: clip.duration, preferredTimescale: 600)
            )
            
            // Define composition time (where to place on timeline)
            let compositionTime = CMTime(seconds: clip.startTime, preferredTimescale: 600)
            
            // Insert video
            try videoTrack.insertTimeRange(
                sourceTimeRange,
                of: sourceVideoTrack,
                at: compositionTime
            )
            
            // Insert audio if available
            let audioTracks = try await sourceAsset.loadTracks(withMediaType: .audio)
            if let sourceAudioTrack = audioTracks.first {
                try? audioTrack.insertTimeRange(
                    sourceTimeRange,
                    of: sourceAudioTrack,
                    at: compositionTime
                )
            }
        }
        
        return composition
    }
    
    // MARK: - Player Setup
    
    private func setupPlayer() {
        // Player will be created when composition is ready
    }
    
    private func setupPlayerObservers() {
        guard let player = player else { return }
        
        // Observe playing state
        statusObserver = player.publisher(for: \.timeControlStatus)
            .sink { [weak self] status in
                self?.isPlaying = (status == .playing)
            }
    }
    
    // MARK: - Time Observation
    
    private func setupTimeObserver() {
        removeTimeObserver()
        
        guard let player = player else { return }
        
        // Update every 1/30 second
        let interval = CMTime(seconds: 1.0/30.0, preferredTimescale: 600)
        
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: nil) { [weak self] time in
            guard let self = self else { return }
            
            let sequenceTime = time.seconds
            DispatchQueue.main.async {
                self.currentTime = sequenceTime
                self.updateCurrentClip(at: sequenceTime)
                self.updateCurrentCrop(at: sequenceTime)
            }
        }
        
        timeObserverPlayer = player
    }
    
    private func removeTimeObserver() {
        if let observer = timeObserver, let player = timeObserverPlayer {
            player.removeTimeObserver(observer)
            timeObserver = nil
            timeObserverPlayer = nil
        }
    }
    
    // MARK: - Playback Control
    
    func play() {
        player?.play()
    }
    
    func pause() {
        player?.pause()
    }
    
    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }
    
    func seek(to sequenceTime: Double) {
        let clampedTime = max(0, min(sequenceTime, duration))
        let cmTime = CMTime(seconds: clampedTime, preferredTimescale: 600)
        
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] finished in
            guard let self = self, finished else { return }
            DispatchQueue.main.async {
                self.currentTime = clampedTime
                self.updateCurrentClip(at: clampedTime)
                self.updateCurrentCrop(at: clampedTime)
            }
        }
    }
    
    func stepForward(by frames: Int = 1) {
        guard let sequence = sequence else { return }
        let frameRate = sequence.frameRate
        let frameDuration = 1.0 / frameRate
        let newTime = currentTime + (frameDuration * Double(frames))
        seek(to: newTime)
    }
    
    func stepBackward(by frames: Int = 1) {
        guard let sequence = sequence else { return }
        let frameRate = sequence.frameRate
        let frameDuration = 1.0 / frameRate
        let newTime = currentTime - (frameDuration * Double(frames))
        seek(to: newTime)
    }
    
    // MARK: - Shuttle Controls (J/K/L)
    
    /// Shuttle reverse - each press increases reverse speed
    func shuttleReverse() {
        if shuttleSpeed > 0 {
            // Was going forward, stop first
            shuttleSpeed = 0
            pause()
        } else if shuttleSpeed == 0 {
            // Start reverse at normal speed
            shuttleSpeed = -1.0
            player?.rate = shuttleSpeed
            currentRate = shuttleSpeed
        } else {
            // Increase reverse speed
            let currentIndex = Self.shuttleSpeeds.firstIndex { -$0 == shuttleSpeed } ?? 0
            let nextIndex = min(currentIndex + 1, Self.shuttleSpeeds.count - 1)
            shuttleSpeed = -Self.shuttleSpeeds[nextIndex]
            player?.rate = shuttleSpeed
            currentRate = shuttleSpeed
        }
    }
    
    /// Shuttle stop - pause playback
    func shuttleStop() {
        shuttleSpeed = 0
        pause()
        currentRate = 0
    }
    
    /// Shuttle forward - each press increases forward speed
    func shuttleForward() {
        if shuttleSpeed < 0 {
            // Was going reverse, stop first
            shuttleSpeed = 0
            pause()
        } else if shuttleSpeed == 0 {
            // Start forward at normal speed
            shuttleSpeed = 1.0
            play()
            currentRate = shuttleSpeed
        } else {
            // Increase forward speed
            let currentIndex = Self.shuttleSpeeds.firstIndex { $0 == shuttleSpeed } ?? 0
            let nextIndex = min(currentIndex + 1, Self.shuttleSpeeds.count - 1)
            shuttleSpeed = Self.shuttleSpeeds[nextIndex]
            player?.rate = shuttleSpeed
            currentRate = shuttleSpeed
        }
    }
    
    // MARK: - Navigation
    
    func goToStart() {
        seek(to: 0)
    }
    
    func goToEnd() {
        seek(to: max(0, duration - 0.1))
    }
    
    func jumpForward(seconds: Double) {
        let newTime = min(duration, currentTime + seconds)
        seek(to: newTime)
    }
    
    func jumpBackward(seconds: Double) {
        let newTime = max(0, currentTime - seconds)
        seek(to: newTime)
    }
    
    // MARK: - Current Clip Tracking
    
    private func updateCurrentClip(at sequenceTime: Double) {
        guard let sequence = sequence else { return }
        
        let clip = sequence.getClipAt(sequenceTime: sequenceTime)
        
        // Only update if clip changed
        if currentClip?.id != clip?.id {
            currentClip = clip
        }
    }
    
    // MARK: - Crop Interpolation
    
    private func updateCurrentCrop(at sequenceTime: Double) {
        guard let clip = currentClip else {
            currentClipCrop = nil
            return
        }
        
        // Convert sequence time to clip-local time
        let clipLocalTime = clip.clipLocalTime(fromSequenceTime: sequenceTime)
        
        // Check if clip has keyframes
        if clip.cropConfiguration.hasKeyframes {
            // Interpolate keyframes at clip-local time
            currentClipCrop = KeyframeInterpolator.shared.interpolate(
                keyframes: clip.cropConfiguration.keyframes,
                at: clipLocalTime,
                mode: clip.cropConfiguration.mode
            )
        } else {
            // Use static crop configuration
            currentClipCrop = InterpolatedCropState(from: clip.cropConfiguration)
        }
    }
    
    // MARK: - Sequence Updates
    
    /// Call this when the sequence's clip structure changes (add/remove/move clips)
    func sequenceDidChange() {
        guard let sequence = sequence else { return }
        duration = sequence.duration
        rebuildComposition()
    }
    
    /// Call this when a clip's crop changes (no need to rebuild composition)
    func clipCropDidChange() {
        // Just update the current crop interpolation
        updateCurrentCrop(at: currentTime)
    }
}

// MARK: - InterpolatedCropState Helper

extension InterpolatedCropState {
    /// Create a static crop state from a CropConfiguration (no interpolation)
    init(from config: CropConfiguration) {
        self.init(
            cropRect: config.cropRect,
            edgeInsets: config.edgeInsets,
            circleCenter: config.circleCenter,
            circleRadius: config.circleRadius,
            freehandPoints: config.freehandPoints,
            freehandPathData: config.freehandPathData,
            aiMaskData: config.aiMaskData,
            aiBoundingBox: config.aiBoundingBox
        )
    }
}
