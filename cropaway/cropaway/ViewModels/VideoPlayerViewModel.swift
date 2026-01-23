//
//  VideoPlayerViewModel.swift
//  cropaway
//

import Combine
import Foundation
import AVFoundation
import SwiftUI

@MainActor
final class VideoPlayerViewModel: ObservableObject {
    @Published var player: AVPlayer?
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var isPlaying: Bool = false
    @Published var videoSize: CGSize = .zero
    @Published var isLooping: Bool = false
    @Published var currentRate: Float = 1.0

    // Shuttle control state for J/K/L speed ramping
    private var shuttleSpeed: Float = 0
    private static let shuttleSpeeds: [Float] = [0.5, 1.0, 2.0, 4.0, 8.0]

    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()

    // Store weak references for cleanup in deinit
    nonisolated(unsafe) private var playerForCleanup: AVPlayer?
    nonisolated(unsafe) private var observerForCleanup: Any?

    func loadVideo(_ video: VideoItem) {
        // Remove previous observer
        if let observer = timeObserver {
            player?.removeTimeObserver(observer)
            timeObserver = nil
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

        if isLooping {
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime,
                object: player?.currentItem,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.seek(to: 0)
                    self?.play()
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

    deinit {
        if let observer = observerForCleanup {
            playerForCleanup?.removeTimeObserver(observer)
        }
    }
}
