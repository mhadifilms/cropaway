//
//  VideoPlayerViewModel.swift
//  cropaway
//

import Combine
import Foundation
import AVFoundation
import SwiftUI
import Observation

@Observable
@MainActor
final class VideoPlayerViewModel {
    var player: AVPlayer?
    var currentTime: Double = 0
    var duration: Double = 0
    var frameRate: Double = 0
    var isPlaying: Bool = false
    var videoSize: CGSize = .zero
    var isLooping: Bool = false
    var currentRate: Float = 1.0
    var showFrameCount: Bool = false  // Toggle between timecode and frame display
    
    // Current video being played (for timeline sync)
    private(set) var currentVideo: VideoItem?
    
    // Timeline mode: when active, player represents entire sequence not just one clip
    weak var timelineViewModel: TimelineViewModel?
    var isTimelineMode: Bool {
        timelineViewModel?.isTimelinePanelVisible ?? false && timelineViewModel?.activeTimeline != nil
    }
    
    /// Effective duration accounts for timeline mode (entire sequence vs single clip)
    var effectiveDuration: Double {
        if isTimelineMode, let timeline = timelineViewModel?.activeTimeline {
            return timeline.totalDuration
        }
        return duration
    }
    
    /// Effective current time accounts for timeline mode (position in sequence vs clip)
    var effectiveCurrentTime: Double {
        if isTimelineMode,
           let timeline = timelineViewModel?.activeTimeline,
           let selectedClip = timelineViewModel?.selectedClip,
           let clipIndex = timelineViewModel?.selectedClipIndex {
            let clipStart = timeline.startTime(forClipAt: clipIndex)
            return clipStart + currentTime
        }
        return currentTime
    }

    // Shuttle control state for J/K/L speed ramping
    private var shuttleSpeed: Float = 0
    private static let shuttleSpeeds: [Float] = [0.5, 1.0, 2.0, 4.0, 8.0]

    @ObservationIgnored private var timeObserver: Any?
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var metadataCancellable: AnyCancellable?

    // Store weak references for cleanup in deinit
    nonisolated(unsafe) private var playerForCleanup: AVPlayer?
    nonisolated(unsafe) private var observerForCleanup: Any?

    func loadVideo(_ video: VideoItem) {
        // Store current video
        currentVideo = video
        
        // Remove previous observer
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
        }

        // Subscribe to frame rate from metadata
        metadataCancellable?.cancel()
        frameRate = video.metadata.frameRate
        metadataCancellable = video.metadata.$frameRate
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                self?.frameRate = value
            }

        let asset = video.getAsset()
        let playerItem = AVPlayerItem(asset: asset)

        if player == nil {
            player = AVPlayer(playerItem: playerItem)
        } else {
            player?.replaceCurrentItem(with: playerItem)
        }

        // Get duration
        Task {
            do {
                let duration = try await asset.load(.duration)
                self.duration = duration.seconds
            } catch {
                self.duration = 0
            }
        }

        // Get video size
        Task {
            if let track = await asset.videoTrack {
                do {
                    let size = try await track.load(.naturalSize)
                    let transform = try await track.load(.preferredTransform)
                    let transformedSize = size.applying(transform)
                    self.videoSize = CGSize(
                        width: abs(transformedSize.width),
                        height: abs(transformedSize.height)
                    )
                } catch {
                    self.videoSize = .zero
                }
            }
        }

        // Add time observer
        let interval = CMTime(seconds: 1.0 / 30.0, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self else { return }
            Task { @MainActor [weak self] in
                self?.currentTime = time.seconds
            }
        }

        // Store for cleanup
        playerForCleanup = player
        observerForCleanup = timeObserver

        // Observe playback status
        player?.publisher(for: \.timeControlStatus)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.isPlaying = status == .playing
            }
            .store(in: &cancellables)
        
        // Preroll and seek to first frame to ensure it loads immediately
        // This fixes the "black first frame" issue
        Task {
            // Wait for player item to be ready
            guard let playerItem = player?.currentItem else { return }
            guard let player = player else { return }
            
            // Wait for player status to be ready
            while player.status != .readyToPlay {
                try? await Task.sleep(nanoseconds: 10_000_000) // 0.01 seconds
                if player.currentItem != playerItem { return } // Item changed, abort
            }
            
            // Seek to a tiny bit forward (0.01 seconds) then back to 0
            // This forces AVPlayer to load and display the first frame
            let firstFrameTime = CMTime(seconds: 0.01, preferredTimescale: 600)
            await playerItem.seek(to: firstFrameTime, toleranceBefore: .zero, toleranceAfter: .zero)
            
            // Now seek back to actual start
            let zeroTime = CMTime.zero
            await playerItem.seek(to: zeroTime, toleranceBefore: .zero, toleranceAfter: .zero)
            
            // Preroll at rate 0 to load the frame without playing
            await player.preroll(atRate: 0)
        }
    }

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

    func seek(to time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 600)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
    
    /// Seek to a global time, handling both single video and timeline modes
    func seekGlobal(to time: Double) {
        if isTimelineMode {
            timelineViewModel?.seek(to: time)
        } else {
            seek(to: time)
        }
    }

    func seekRelative(_ delta: Double) {
        let newTime = max(0, min(duration, currentTime + delta))
        seek(to: newTime)
    }

    func stepForward() {
        if let item = player?.currentItem {
            item.step(byCount: 1)
        }
    }

    func stepBackward() {
        if let item = player?.currentItem {
            item.step(byCount: -1)
        }
    }

    func playReverse() {
        // AVPlayer supports negative playback rates
        player?.rate = -1.0
        currentRate = -1.0
        shuttleSpeed = -1.0
    }

    func setPlaybackRate(_ rate: Float) {
        player?.rate = rate
        currentRate = rate
        shuttleSpeed = rate
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

    // MARK: - Loop Playback

    func toggleLoop() {
        isLooping.toggle()
        setupLoopObserver()
    }

    private func setupLoopObserver() {
        // Remove existing observer
        if let observer = endObserver {
            NotificationCenter.default.removeObserver(observer)
            endObserver = nil
        }

        // Always observe end time for either looping or timeline auto-advance
        if isLooping || isTimelineMode {
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player?.currentItem,
                queue: .main
            ) { [weak self] _ in
                guard let self = self else { return }
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    
                    // Handle timeline mode: advance to next clip
                    if self.isTimelineMode {
                        let wasPlaying = self.isPlaying
                        
                        // Try to go to next clip
                        if let timelineVM = self.timelineViewModel,
                           let currentIndex = timelineVM.selectedClipIndex,
                           let timeline = timelineVM.activeTimeline,
                           currentIndex < timeline.clips.count - 1 {
                            // Load next clip
                            timelineVM.goToNextClip()
                            
                            // Continue playing if was playing
                            if wasPlaying {
                                // Small delay to let the new video load
                                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                                self.play()
                            }
                        } else if self.isLooping {
                            // If at end of timeline and looping is on, restart from beginning
                            self.timelineViewModel?.seek(to: 0)
                            if wasPlaying {
                                self.play()
                            }
                        }
                    } else if self.isLooping {
                        // Regular single-video looping
                        self.seek(to: 0)
                        self.play()
                    }
                }
            }
        }
    }

    // MARK: - Rate Display

    var rateDisplayString: String {
        if currentRate == 0 {
            return ""
        } else if currentRate == 1.0 {
            return ""
        } else if currentRate == -1.0 {
            return "Reverse"
        } else if currentRate < 0 {
            return String(format: "%.1fx Reverse", -currentRate)
        } else {
            return String(format: "%.1fx", currentRate)
        }
    }
    
    // MARK: - Frame Count Display
    
    var totalFrameCount: Int {
        guard duration > 0, frameRate > 0 else { return 0 }
        let frames = Int((duration * frameRate).rounded(.down))
        return max(frames, 1)
    }
    
    var currentFrameIndex: Int {
        guard frameRate > 0 else { return 0 }
        let frame = Int((currentTime * frameRate).rounded(.down))
        let lastIndex = max(totalFrameCount - 1, 0)
        return min(max(frame, 0), lastIndex)
    }
    
    var frameDisplayString: String {
        let lastIndex = max(totalFrameCount - 1, 0)
        return "\(currentFrameIndex) / \(lastIndex)"
    }
    
    // MARK: - Timecode Display
    
    var timecodeDisplayString: String {
        return "\(currentTime.smpteTimecode(fps: frameRate)) / \(duration.smpteTimecode(fps: frameRate))"
    }
    
    func toggleTimeDisplay() {
        showFrameCount.toggle()
    }

    // MARK: - Frame Capture

    /// Capture the current frame as an NSImage
    func captureCurrentFrame() async -> NSImage? {
        guard let player = player,
              let currentItem = player.currentItem,
              let asset = currentItem.asset as? AVURLAsset else {
            return nil
        }

        let time = player.currentTime()
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceAfter = .zero
        generator.requestedTimeToleranceBefore = .zero

        do {
            let (cgImage, _) = try await generator.image(at: time)
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            print("Frame capture error: \(error)")
            return nil
        }
    }

    deinit {
        if let observer = observerForCleanup {
            playerForCleanup?.removeTimeObserver(observer)
        }
    }
}
