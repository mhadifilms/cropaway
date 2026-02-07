//
//  TimelineViewModel.swift
//  cropaway
//

import Foundation
import Combine
import AppKit

/// ViewModel for managing timeline/sequence state and operations
@MainActor
final class TimelineViewModel: ObservableObject {

    // MARK: - Published Properties

    /// The current timeline being edited (nil when not in sequence mode)
    @Published var timeline: Timeline?

    /// Whether sequence mode is active
    @Published var isSequenceMode: Bool = false

    /// Currently selected clip ID
    @Published var selectedClipID: UUID?

    /// Currently selected transition ID (for editing)
    @Published var selectedTransitionID: UUID?

    /// Current playhead position in the timeline (seconds)
    @Published var playheadTime: Double = 0

    /// Whether dragging is in progress
    @Published var isDragging: Bool = false

    /// Index being dragged (for reordering)
    @Published var draggingClipIndex: Int?

    private var cancellables = Set<AnyCancellable>()

    // MARK: - Computed Properties

    /// The currently selected clip
    var selectedClip: TimelineClip? {
        guard let id = selectedClipID else { return nil }
        return timeline?.clips.first { $0.id == id }
    }

    /// The currently selected transition
    var selectedTransition: ClipTransition? {
        guard let id = selectedTransitionID else { return nil }
        return timeline?.transitions.first { $0.id == id }
    }

    /// Index of the currently selected clip
    var selectedClipIndex: Int? {
        guard let id = selectedClipID else { return nil }
        return timeline?.clips.firstIndex { $0.id == id }
    }

    /// Total duration of the timeline
    var totalDuration: Double {
        timeline?.totalDuration ?? 0
    }

    /// Number of clips in the timeline
    var clipCount: Int {
        timeline?.clipCount ?? 0
    }

    /// Whether there are multiple clips (transitions possible)
    var hasMultipleClips: Bool {
        timeline?.hasMultipleClips ?? false
    }

    // MARK: - Initialization

    init() {
        setupObservers()
    }

    private func setupObservers() {
        // When sequence mode is disabled, clear the timeline
        $isSequenceMode
            .dropFirst()
            .filter { !$0 }
            .sink { [weak self] _ in
                self?.timeline = nil
                self?.selectedClipID = nil
                self?.selectedTransitionID = nil
                self?.playheadTime = 0
            }
            .store(in: &cancellables)
    }

    // MARK: - Sequence Mode

    /// Enter sequence mode with a new empty timeline
    func enterSequenceMode() {
        isSequenceMode = true
        if timeline == nil {
            timeline = Timeline()
        }
    }

    /// Exit sequence mode
    func exitSequenceMode() {
        isSequenceMode = false
    }

    /// Toggle sequence mode
    func toggleSequenceMode() {
        if isSequenceMode {
            exitSequenceMode()
        } else {
            enterSequenceMode()
        }
    }

    // MARK: - Sequence Creation

    /// Create a new timeline from an array of videos
    func createSequence(from videos: [VideoItem]) {
        let newTimeline = Timeline(name: "Sequence \(Date().formatted(date: .abbreviated, time: .shortened))")

        for video in videos {
            newTimeline.addClip(from: video)
        }

        timeline = newTimeline
        isSequenceMode = true

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
        guard let timeline = timeline else {
            // Create new timeline if none exists
            createSequence(from: [video])
            return
        }

        timeline.addClip(from: video)
        objectWillChange.send()

        // Select the new clip
        if let newClip = timeline.clips.last {
            selectedClipID = newClip.id
        }
    }

    /// Add a clip at a specific index
    func insertClip(from video: VideoItem, at index: Int) {
        guard let timeline = timeline else { return }

        let clip = TimelineClip(videoItem: video)
        timeline.insertClip(clip, at: index)
        objectWillChange.send()

        selectedClipID = clip.id
    }

    /// Remove a clip by ID
    func removeClip(id: UUID) {
        guard let timeline = timeline else { return }

        if let index = timeline.clips.firstIndex(where: { $0.id == id }) {
            timeline.removeClip(at: index)
            objectWillChange.send()

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
        guard let timeline = timeline else { return }

        timeline.moveClip(from: sourceIndex, to: destinationIndex)
        objectWillChange.send()
    }

    /// Split the currently selected clip at the playhead position
    func splitSelectedClipAtPlayhead() -> Bool {
        guard let timeline = timeline,
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
            objectWillChange.send()
        }
        return success
    }

    // MARK: - Selection

    /// Select a clip by ID
    func selectClip(id: UUID) {
        selectedClipID = id
        selectedTransitionID = nil

        // Seek to clip start
        if let timeline = timeline,
           let index = timeline.clips.firstIndex(where: { $0.id == id }) {
            playheadTime = timeline.startTime(forClipAt: index)
        }
    }

    /// Select a clip by index
    func selectClip(at index: Int) {
        guard let timeline = timeline,
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
        if let transition = timeline?.transition(afterClipIndex: index) {
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
        objectWillChange.send()
    }

    /// Set the out point for the selected clip
    func setOutPoint(at time: Double) {
        guard let clip = selectedClip else { return }
        clip.setOutPointFromTime(time)
        objectWillChange.send()
    }

    /// Set in point at current playhead position
    func setInPointAtPlayhead() {
        guard let timeline = timeline,
              let clipIndex = selectedClipIndex else { return }

        let clipStartTime = timeline.startTime(forClipAt: clipIndex)
        let timeInClip = playheadTime - clipStartTime
        setInPoint(at: timeInClip)
    }

    /// Set out point at current playhead position
    func setOutPointAtPlayhead() {
        guard let timeline = timeline,
              let clipIndex = selectedClipIndex else { return }

        let clipStartTime = timeline.startTime(forClipAt: clipIndex)
        let timeInClip = playheadTime - clipStartTime
        setOutPoint(at: timeInClip)
    }

    // MARK: - Transition Operations

    /// Set the transition type after a clip
    func setTransitionType(afterClipIndex index: Int, type: TransitionType) {
        timeline?.setTransitionType(afterClipIndex: index, type: type)
        objectWillChange.send()
    }

    /// Set the transition duration after a clip
    func setTransitionDuration(afterClipIndex index: Int, duration: Double) {
        timeline?.setTransitionDuration(afterClipIndex: index, duration: duration)
        objectWillChange.send()
    }

    /// Get the transition after a clip index
    func transition(afterClipIndex index: Int) -> ClipTransition? {
        timeline?.transition(afterClipIndex: index)
    }

    // MARK: - Playhead / Seeking

    /// Seek to a specific time in the timeline
    func seek(to time: Double) {
        playheadTime = max(0, min(totalDuration, time))
    }

    /// Get the clip and time within it for the current playhead position
    func currentClipInfo() -> (clip: TimelineClip, clipIndex: Int, timeInClip: Double)? {
        timeline?.clip(at: playheadTime)
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
