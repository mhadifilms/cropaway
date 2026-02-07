//
//  TimelineViewModel.swift
//  cropaway
//

import Foundation
import Combine
import AppKit
import Observation

/// ViewModel for managing timeline/sequence state and operations
@Observable
@MainActor
final class TimelineViewModel {

    // MARK: - Published Properties

    /// All open timelines (can have multiple)
    var timelines: [Timeline] = []
    
    /// The currently active timeline being edited
    var activeTimeline: Timeline?
    
    /// Whether timeline panel is visible
    var isTimelinePanelVisible: Bool = false

    /// Currently selected clip ID in active timeline
    var selectedClipID: UUID?

    /// Currently selected transition ID (for editing)
    var selectedTransitionID: UUID?

    /// Current playhead position in the timeline (seconds)
    /// This is computed from the player when active, not stored independently
    var playheadTime: Double = 0
    
    /// Reference to the video player for synchronization
    weak var videoPlayer: VideoPlayerViewModel?

    /// Whether dragging is in progress
    var isDragging: Bool = false

    /// Index being dragged (for reordering)
    var draggingClipIndex: Int?

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    
    /// Track last video load to prevent rapid switching during scrubbing
    private var lastVideoLoadTime: TimeInterval = 0
    private let minVideoLoadInterval: TimeInterval = 0.2 // 200ms between video switches
    
    /// Legacy support - maps to activeTimeline for backward compatibility
    var timeline: Timeline? {
        get { activeTimeline }
        set { activeTimeline = newValue }
    }
    
    /// Legacy support - maps to panel visibility
    var isSequenceMode: Bool {
        get { isTimelinePanelVisible && activeTimeline != nil }
        set { isTimelinePanelVisible = newValue }
    }

    // MARK: - Computed Properties

    /// The currently selected clip
    var selectedClip: TimelineClip? {
        guard let id = selectedClipID else { return nil }
        return activeTimeline?.clips.first { $0.id == id }
    }

    /// The currently selected transition
    var selectedTransition: ClipTransition? {
        guard let id = selectedTransitionID else { return nil }
        return activeTimeline?.transitions.first { $0.id == id }
    }

    /// Index of the currently selected clip
    var selectedClipIndex: Int? {
        guard let id = selectedClipID else { return nil }
        return activeTimeline?.clips.firstIndex { $0.id == id }
    }

    /// Total duration of the timeline
    var totalDuration: Double {
        activeTimeline?.totalDuration ?? 0
    }

    /// Number of clips in the timeline
    var clipCount: Int {
        activeTimeline?.clipCount ?? 0
    }

    /// Whether there are multiple clips (transitions possible)
    var hasMultipleClips: Bool {
        activeTimeline?.hasMultipleClips ?? false
    }

    // MARK: - Initialization

    init() {
        setupObservers()
    }

    private func setupObservers() {
        // Note: With @Observable, changes are automatically tracked
        // No manual observation setup needed
    }

    // MARK: - Timeline Panel Management

    /// Toggle timeline panel visibility with optional starting video
    func toggleTimelinePanel(startingWith video: VideoItem? = nil) {
        isTimelinePanelVisible.toggle()
        
        // If showing panel and no active timeline, create one with the current video
        if isTimelinePanelVisible && activeTimeline == nil {
            if let video = video {
                createSequence(from: [video])
            } else {
                createNewTimeline()
            }
        }
    }
    
    /// Create a new timeline
    @discardableResult
    func createNewTimeline() -> Timeline {
        let timeline = Timeline()
        timelines.append(timeline)
        activeTimeline = timeline
        return timeline
    }
    
    /// Set the active timeline
    func setActiveTimeline(_ timeline: Timeline) {
        activeTimeline = timeline
        isTimelinePanelVisible = true
    }
    
    /// Close a timeline
    func closeTimeline(_ timeline: Timeline) {
        timelines.removeAll { $0.id == timeline.id }
        if activeTimeline?.id == timeline.id {
            activeTimeline = timelines.first
        }
        if timelines.isEmpty {
            isTimelinePanelVisible = false
        }
    }

    // MARK: - Sequence Creation

    /// Create a new timeline from an array of videos
    func createSequence(from videos: [VideoItem]) {
        let newTimeline = Timeline(name: "Sequence \(Date().formatted(date: .abbreviated, time: .shortened))")

        for video in videos {
            newTimeline.addClip(from: video)
        }

        timelines.append(newTimeline)
        activeTimeline = newTimeline
        isTimelinePanelVisible = true

        // Select first clip
        if let firstClip = newTimeline.clips.first {
            selectedClipID = firstClip.id
        }
    }

    /// Create a sequence from two videos (drag one onto another)
    func createSequence(from firstVideo: VideoItem, and secondVideo: VideoItem) {
        createSequence(from: [firstVideo, secondVideo])
    }

    // MARK: - Clip Management

    /// Add a video to the current sequence
    func addClip(from video: VideoItem) {
        guard let timeline = activeTimeline else {
            // Create new timeline if none exists
            createSequence(from: [video])
            return
        }

        timeline.addClip(from: video)
        
        // Force a refresh to ensure UI updates
        Task { @MainActor in
            // Changes tracked automatically with @Observable
            
            // Select the new clip
            if let newClip = timeline.clips.last {
                selectedClipID = newClip.id
            }
        }
    }

    /// Add a clip at a specific index
    func insertClip(from video: VideoItem, at index: Int) {
        guard let timeline = activeTimeline else { return }

        let clip = TimelineClip(videoItem: video)
        timeline.insertClip(clip, at: index)
        // Changes tracked automatically

        selectedClipID = clip.id
    }

    /// Remove a clip by ID
    func removeClip(id: UUID) {
        guard let timeline = activeTimeline else { return }

        if let index = timeline.clips.firstIndex(where: { $0.id == id }) {
            timeline.removeClip(at: index)
            // Changes tracked automatically

            // Select adjacent clip if possible
            if selectedClipID == id {
                if index < timeline.clips.count {
                    selectedClipID = timeline.clips[index].id
                } else if !timeline.clips.isEmpty {
                    selectedClipID = timeline.clips[timeline.clips.count - 1].id
                } else {
                    selectedClipID = nil
                }
            }
        }
    }

    /// Remove the currently selected clip
    func removeSelectedClip() {
        guard let id = selectedClipID else { return }
        removeClip(id: id)
    }

    /// Reorder a clip from one position to another
    func reorderClip(from sourceIndex: Int, to destinationIndex: Int) {
        guard let timeline = activeTimeline else { return }

        timeline.moveClip(from: sourceIndex, to: destinationIndex)
        // Changes tracked automatically
    }

    /// Split the currently selected clip at the playhead position
    func splitSelectedClipAtPlayhead() -> Bool {
        guard let timeline = activeTimeline,
              let clipIndex = selectedClipIndex,
              let clip = selectedClip else { return false }

        // Calculate time within the clip
        let clipStartTime = timeline.startTime(forClipAt: clipIndex)
        let timeInClip = playheadTime - clipStartTime

        // Validate split position
        guard timeInClip > 0.1 && timeInClip < clip.trimmedDuration - 0.1 else {
            return false
        }

        let success = timeline.splitClip(at: clipIndex, atTime: timeInClip)
        if success {
            // Changes tracked automatically
        }
        return success
    }
    
    // MARK: - Transition Management
    
    /// Add a manual transition after a specific clip
    func addTransition(afterClipIndex: Int, type: TransitionType = .cut) {
        guard let timeline = activeTimeline else { return }
        
        // Check if transition already exists
        if timeline.transition(afterClipIndex: afterClipIndex) != nil {
            return // Already has transition
        }
        
        // Validate index
        guard afterClipIndex >= 0 && afterClipIndex < timeline.clips.count - 1 else {
            return
        }
        
        let transition = ClipTransition(type: type, afterClipIndex: afterClipIndex)
        timeline.transitions.append(transition)
        // Changes tracked automatically
    }
    
    /// Remove a transition after a specific clip
    func removeTransition(afterClipIndex: Int) {
        guard let timeline = activeTimeline else { return }
        timeline.transitions.removeAll { $0.afterClipIndex == afterClipIndex }
        // Changes tracked automatically
    }
    
    /// Update an existing transition's type
    func updateTransition(afterClipIndex: Int, type: TransitionType) {
        guard let timeline = activeTimeline else { return }
        
        if let index = timeline.transitions.firstIndex(where: { $0.afterClipIndex == afterClipIndex }) {
            let oldTransition = timeline.transitions[index]
            timeline.transitions[index] = ClipTransition(
                id: oldTransition.id,
                type: type,
                duration: oldTransition.duration,
                afterClipIndex: afterClipIndex
            )
            // Changes tracked automatically
        }
    }

    // MARK: - Selection

    /// Select a clip by ID
    func selectClip(id: UUID) {
        selectedClipID = id
        selectedTransitionID = nil

        // Seek to clip start
        if let timeline = activeTimeline,
           let index = timeline.clips.firstIndex(where: { $0.id == id }) {
            playheadTime = timeline.startTime(forClipAt: index)
        }
    }

    /// Select a clip by index
    func selectClip(at index: Int) {
        guard let timeline = activeTimeline,
              index >= 0 && index < timeline.clips.count else { return }
        selectClip(id: timeline.clips[index].id)
    }

    /// Select a transition by ID
    func selectTransition(id: UUID) {
        selectedTransitionID = id
        selectedClipID = nil
    }

    /// Select a transition by the clip index it follows
    func selectTransition(afterClipIndex index: Int) {
        if let transition = activeTimeline?.transition(afterClipIndex: index) {
            selectTransition(id: transition.id)
        }
    }

    /// Deselect all
    func deselectAll() {
        selectedClipID = nil
        selectedTransitionID = nil
    }

    // MARK: - Trim Operations

    /// Set the in point for the selected clip
    func setInPoint(at time: Double) {
        guard let clip = selectedClip else { return }
        clip.setInPointFromTime(time)
        // Changes tracked automatically
    }

    /// Set the out point for the selected clip
    func setOutPoint(at time: Double) {
        guard let clip = selectedClip else { return }
        clip.setOutPointFromTime(time)
        // Changes tracked automatically
    }

    /// Set in point at current playhead position
    func setInPointAtPlayhead() {
        guard let timeline = activeTimeline,
              let clipIndex = selectedClipIndex else { return }

        let clipStartTime = timeline.startTime(forClipAt: clipIndex)
        let timeInClip = playheadTime - clipStartTime
        setInPoint(at: timeInClip)
    }

    /// Set out point at current playhead position
    func setOutPointAtPlayhead() {
        guard let timeline = activeTimeline,
              let clipIndex = selectedClipIndex else { return }

        let clipStartTime = timeline.startTime(forClipAt: clipIndex)
        let timeInClip = playheadTime - clipStartTime
        setOutPoint(at: timeInClip)
    }

    // MARK: - Transition Operations

    /// Set the transition type after a clip
    func setTransitionType(afterClipIndex index: Int, type: TransitionType) {
        activeTimeline?.setTransitionType(afterClipIndex: index, type: type)
        // Changes tracked automatically
    }

    /// Set the transition duration after a clip
    func setTransitionDuration(afterClipIndex index: Int, duration: Double) {
        activeTimeline?.setTransitionDuration(afterClipIndex: index, duration: duration)
        // Changes tracked automatically
    }

    /// Get the transition after a clip index
    func transition(afterClipIndex index: Int) -> ClipTransition? {
        activeTimeline?.transition(afterClipIndex: index)
    }

    // MARK: - Playhead / Seeking

    /// Seek to a specific time in the timeline
    func seek(to time: Double) {
        let clampedTime = max(0, min(totalDuration, time))
        playheadTime = clampedTime
        
        // If we have an active timeline and player, seek the player to the corresponding clip
        if let timeline = activeTimeline, let player = videoPlayer {
            if let (clip, clipIndex, timeInClip) = timeline.clip(at: clampedTime), let video = clip.videoItem {
                // Update selected clip
                selectedClipID = clip.id
                
                // If the clip's video isn't loaded in the player, load it
                if player.currentVideo?.id != video.id {
                    // Throttle video loading to prevent overwhelming AVPlayer
                    let now = Date().timeIntervalSince1970
                    guard now - lastVideoLoadTime >= minVideoLoadInterval else {
                        // Too soon since last video load, skip this seek
                        return
                    }
                    lastVideoLoadTime = now
                    
                    player.loadVideo(video)
                    
                    // Wait for video to load before seeking
                    Task {
                        // Give AVPlayer time to load the new video
                        try? await Task.sleep(nanoseconds: 150_000_000) // 0.15 seconds
                        
                        // Check if we're still trying to seek to the same clip
                        if player.currentVideo?.id == video.id {
                            await MainActor.run {
                                player.seek(to: timeInClip)
                            }
                        }
                    }
                } else {
                    // Same video, just seek
                    player.seek(to: timeInClip)
                }
            }
        }
    }

    /// Get the clip and time within it for the current playhead position
    func currentClipInfo() -> (clip: TimelineClip, clipIndex: Int, timeInClip: Double)? {
        activeTimeline?.clip(at: playheadTime)
    }

    /// Navigate to the next clip
    func goToNextClip() {
        guard let timeline = timeline,
              let currentIndex = selectedClipIndex,
              currentIndex < timeline.clips.count - 1 else { return }

        selectClip(at: currentIndex + 1)
    }

    /// Navigate to the previous clip
    func goToPreviousClip() {
        guard let currentIndex = selectedClipIndex,
              currentIndex > 0 else { return }

        selectClip(at: currentIndex - 1)
    }

    // MARK: - Drag and Drop

    /// Start dragging a clip for reorder
    func startDraggingClip(at index: Int) {
        isDragging = true
        draggingClipIndex = index
    }

    /// End dragging
    func endDragging() {
        isDragging = false
        draggingClipIndex = nil
    }

    /// Handle a video being dropped onto the timeline
    func handleVideoDrop(_ video: VideoItem, at index: Int?) {
        if let index = index {
            insertClip(from: video, at: index)
        } else {
            addClip(from: video)
        }
    }
}
