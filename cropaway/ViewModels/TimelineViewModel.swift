//
//  TimelineViewModel.swift
//  cropaway
//

import Foundation
import Combine
import AppKit
import Observation

/// Direction for moving tracks
enum TrackMoveDirection {
    case up
    case down
}

/// ViewModel for managing timeline/sequence state and operations
@Observable
@MainActor
final class TimelineViewModel {

    // MARK: - Published Properties

    /// All open timelines (can have multiple)
    var timelines: [Timeline] = []
    
    /// The currently active timeline being edited
    var activeTimeline: Timeline?
    
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
    
    /// PHASE 8: Magnetic snapping enabled (snaps to clips, playhead, markers)
    var magneticSnappingEnabled: Bool = true
    
    /// PHASE 8: Snap threshold in seconds (how close to snap)
    var snapThreshold: Double = 0.1  // 100ms / 3 frames at 30fps

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private let storageService = TimelineStorageService.shared
    
    /// Track last video load to prevent rapid switching during scrubbing
    private var lastVideoLoadTime: TimeInterval = 0
    private let minVideoLoadInterval: TimeInterval = 0.2 // 200ms between video switches
    
    /// Track last save time to debounce auto-saves
    private var lastSaveTime: TimeInterval = 0
    private let minSaveInterval: TimeInterval = 2.0 // 2 seconds between auto-saves
    
    /// PHASE 10: Auto-save timer (saves every 30 seconds)
    @ObservationIgnored private var autoSaveTimer: Timer?
    private let autoSaveInterval: TimeInterval = 30.0 // 30 seconds
    
    /// PHASE 10: Undo/redo manager for timeline operations
    let undoManager = TimelineUndoManager()
    
    /// Legacy support - maps to activeTimeline for backward compatibility
    var timeline: Timeline? {
        get { activeTimeline }
        set { activeTimeline = newValue }
    }
    
    /// Legacy support - always true now (timeline always visible)
    var isSequenceMode: Bool {
        get { activeTimeline != nil }
        set { /* Timeline always visible in Phase 7 */ }
    }

    // MARK: - Computed Properties

    /// The currently selected clip
    var selectedClip: TimelineClip? {
        guard let id = selectedClipID else { return nil }
        return activeTimeline?.findClip(withID: id)  // Use multi-track finder
    }

    /// The currently selected transition
    var selectedTransition: ClipTransition? {
        guard let id = selectedTransitionID else { return nil }
        return activeTimeline?.transitions.first { $0.id == id }
    }

    /// Index of the currently selected clip (in its track)
    var selectedClipIndex: Int? {
        guard let id = selectedClipID else { return nil }
        return activeTimeline?.findClipLocation(withID: id)?.clipIndex
    }

    /// Total duration of the timeline
    var totalDuration: Double {
        activeTimeline?.totalDuration ?? 0
    }

    /// Number of clips in the timeline (across all tracks)
    var clipCount: Int {
        activeTimeline?.allClips.count ?? 0
    }

    /// Whether there are multiple clips (transitions possible)
    var hasMultipleClips: Bool {
        (activeTimeline?.allClips.count ?? 0) > 1
    }

    // MARK: - Initialization

    init() {
        setupObservers()
        loadAllTimelines()
        
        // PHASE 7: Ensure a default timeline always exists for timeline-first UI
        if activeTimeline == nil {
            let defaultTimeline = Timeline(name: "Sequence 1")
            timelines.append(defaultTimeline)
            activeTimeline = defaultTimeline
        }
        
        // PHASE 10: Wire up undo manager
        undoManager.timeline = activeTimeline
        
        // PHASE 10: Start auto-save timer
        startAutoSaveTimer()
    }
    
    deinit {
        autoSaveTimer?.invalidate()
    }

    private func setupObservers() {
        // Observe changes to active timeline
        // When timeline changes, set up observers for its clips
        // Note: This will be called whenever activeTimeline is set
    }

    /// Set up observers for the active timeline's clips
    private func observeActiveTimeline() {
        cancellables.removeAll()

        guard let timeline = activeTimeline else { return }

        // Observe each clip's trim point changes across ALL tracks
        for clip in timeline.allClips {
            clip.$inPoint
                .dropFirst()  // Skip initial value
                .sink { [weak self] _ in
                    Task { @MainActor in
                        self?.rebuildComposition()
                    }
                }
                .store(in: &cancellables)

            clip.$outPoint
                .dropFirst()
                .sink { [weak self] _ in
                    Task { @MainActor in
                        self?.rebuildComposition()
                    }
                }
                .store(in: &cancellables)
        }

        // Observe timeline's tracks array changes (multi-track support)
        timeline.$tracks
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.observeActiveTimeline()  // Re-observe new clips
                    self?.rebuildComposition()
                }
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Auto-Save (Phase 10)
    
    /// Start the auto-save timer
    private func startAutoSaveTimer() {
        autoSaveTimer?.invalidate()
        
        autoSaveTimer = Timer.scheduledTimer(withTimeInterval: autoSaveInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.performAutoSave()
            }
        }
        
        print("✅ Auto-save enabled: saving every \(Int(autoSaveInterval))s")
    }
    
    /// Perform auto-save if there's an active timeline
    private func performAutoSave() {
        guard let timeline = activeTimeline else { return }
        
        // Only save if timeline has clips or has been modified
        guard !timeline.allClips.isEmpty || timeline.inPoint != nil || timeline.outPoint != nil else {
            return
        }
        
        do {
            try storageService.save(timeline)
            print("💾 Auto-saved timeline: \(timeline.name)")
        } catch {
            print("⚠️ Auto-save failed: \(error)")
        }
    }
    
    // MARK: - Persistence
    
    /// Load all saved timelines on startup
    private func loadAllTimelines() {
        let loadedTimelines = storageService.loadAll()
        timelines = loadedTimelines
        
        // PHASE 7: Set most recent as active if available (timeline always visible now)
        if let mostRecent = loadedTimelines.first {
            activeTimeline = mostRecent
        }
    }
    
    /// Save the active timeline (debounced)
    func saveActiveTimeline() {
        guard let timeline = activeTimeline else { return }
        
        // Debounce saves to avoid overwhelming disk I/O
        let now = Date().timeIntervalSince1970
        guard now - lastSaveTime >= minSaveInterval else { return }
        lastSaveTime = now
        
        Task.detached {
            do {
                try await MainActor.run {
                    try self.storageService.save(timeline)
                }
            } catch {
                print("⚠️ Failed to save timeline: \(error)")
            }
        }
    }
    
    /// Resolve video items after loading timeline
    func resolveVideoItems(from videos: [VideoItem]) {
        activeTimeline?.resolveVideoItems(from: videos)
    }

    // MARK: - Timeline Panel Management

    /// Toggle timeline panel visibility with optional starting video
    /// PHASE 7: Timeline always visible now - this just creates sequences if needed
    func toggleTimelinePanel(startingWith video: VideoItem? = nil) {
        // If no active timeline, create one with the current video
        if activeTimeline == nil {
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
        observeActiveTimeline()  // NEW: Set up observers
        return timeline
    }
    
    /// Set the active timeline
    func setActiveTimeline(_ timeline: Timeline) {
        activeTimeline = timeline
        observeActiveTimeline()  // NEW: Set up observers
    }
    
    /// Close a timeline
    func closeTimeline(_ timeline: Timeline) {
        timelines.removeAll { $0.id == timeline.id }
        if activeTimeline?.id == timeline.id {
            activeTimeline = timelines.first
        }
    }
    
    /// Delete a timeline (close and remove from storage)
    func deleteTimeline(_ timeline: Timeline) {
        closeTimeline(timeline)
        try? storageService.delete(timeline)
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
        observeActiveTimeline()  // NEW: Set up observers

        // Select first clip
        if let firstClip = newTimeline.allClips.first {
            selectedClipID = firstClip.id
        }

        // Build composition for seamless playback
        rebuildComposition()
        
        // Save new timeline
        saveActiveTimeline()
    }

    /// Create a sequence from two videos (drag one onto another)
    func createSequence(from firstVideo: VideoItem, and secondVideo: VideoItem) {
        createSequence(from: [firstVideo, secondVideo])
    }

    // MARK: - Composition Management

    /// Rebuild the player composition from the active timeline
    /// Call this whenever clips are added, removed, reordered, or trimmed
    func rebuildComposition() {
        guard let timeline = activeTimeline else { return }
        
        // Only rebuild if we have clips (check across all tracks)
        guard !timeline.allClips.isEmpty else { return }
        
        // Load the composition into the player
        videoPlayer?.loadComposition(from: timeline)
        
        // PHASE 10: Pre-warm thumbnail cache for visible clips
        Task {
            await prewarmVisibleClipThumbnails()
        }
    }
    
    /// PHASE 10: Pre-warm thumbnail cache for currently visible clips
    private func prewarmVisibleClipThumbnails() async {
        guard let timeline = activeTimeline else { return }
        
        // Generate thumbnails for first 10 clips across all tracks (likely visible)
        let visibleClips = Array(timeline.allClips.prefix(10))
        
        await withTaskGroup(of: Void.self) { group in
            for clip in visibleClips {
                group.addTask {
                    await clip.generateThumbnailStrip()
                }
            }
        }
    }

    // MARK: - Clip Management

    /// Add a video to the current sequence
    func addClip(from video: VideoItem) {
        guard let timeline = activeTimeline else {
            // Create new timeline if none exists
            createSequence(from: [video])
            rebuildComposition()
            return
        }

        timeline.addClip(from: video)
        
        // Rebuild composition with new clip
        rebuildComposition()
        
        // Force a refresh to ensure UI updates
        Task { @MainActor in
            // Changes tracked automatically with @Observable
            
            // Select the new clip
            if let newClip = timeline.allClips.last {
                selectedClipID = newClip.id
            }
            
            // Auto-save
            saveActiveTimeline()
        }
    }

    /// Add a clip at a specific index
    func insertClip(from video: VideoItem, at index: Int) {
        guard let timeline = activeTimeline else { return }

        let clip = TimelineClip(videoItem: video)
        timeline.insertClip(clip, at: index)
        
        // Rebuild composition
        rebuildComposition()

        selectedClipID = clip.id
    }

    /// Remove a clip by ID
    func removeClip(id: UUID) {
        guard let timeline = activeTimeline else { return }

        if let location = timeline.findClipLocation(withID: id) {
            let index = location.clipIndex
            let track = location.track
            track.clips.remove(at: index)
            
            // Rebuild composition
            rebuildComposition()

            // Select adjacent clip if possible
            if selectedClipID == id {
                if index < track.clips.count {
                    selectedClipID = track.clips[index].id
                } else if !track.clips.isEmpty {
                    selectedClipID = track.clips[track.clips.count - 1].id
                } else {
                    selectedClipID = nil
                }
            }
            
            // Auto-save
            saveActiveTimeline()
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
        
        // Rebuild composition
        rebuildComposition()
        
        // Auto-save
        saveActiveTimeline()
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
    
    // MARK: - Track Management (Phase 4)
    
    /// Add a new video track
    func addVideoTrack() {
        guard let timeline = activeTimeline else { return }
        
        let trackNumber = timeline.videoTracks.count + 1
        let track = Track(
            name: "Video \(trackNumber)",
            clips: [],
            mediaType: .video,
            verticalOrder: timeline.tracks.count
        )
        
        timeline.addTrack(track)
        saveActiveTimeline()
    }
    
    /// Add a new audio track
    func addAudioTrack() {
        guard let timeline = activeTimeline else { return }
        
        let trackNumber = timeline.audioTracks.count + 1
        let track = Track(
            name: "Audio \(trackNumber)",
            clips: [],
            mediaType: .audio,
            verticalOrder: timeline.tracks.count
        )
        
        timeline.addTrack(track)
        saveActiveTimeline()
    }
    
    /// Delete a track
    func deleteTrack(_ track: Track) {
        guard let timeline = activeTimeline else { return }
        
        timeline.removeTrack(track.id)
        rebuildComposition()
        saveActiveTimeline()
    }
    
    /// Move a track up or down
    func moveTrack(_ track: Track, direction: TrackMoveDirection) {
        guard let timeline = activeTimeline else { return }
        
        let tracks = timeline.tracks
        guard let currentIndex = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        
        let newIndex: Int
        switch direction {
        case .up:
            guard currentIndex > 0 else { return }
            newIndex = currentIndex - 1
        case .down:
            guard currentIndex < tracks.count - 1 else { return }
            newIndex = currentIndex + 1
        }
        
        timeline.moveTrack(from: currentIndex, to: newIndex)
        saveActiveTimeline()
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
        guard afterClipIndex >= 0 && afterClipIndex < timeline.allClips.count - 1 else {
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
           let clip = timeline.findClip(withID: id) {
            // Find the clip's global start time
            var currentTime = 0.0
            for track in timeline.tracks {
                for trackClip in track.clips {
                    if trackClip.id == clip.id {
                        playheadTime = currentTime
                        return
                    }
                    currentTime += trackClip.trimmedDuration
                }
            }
        }
    }

    /// Select a clip by index
    func selectClip(at index: Int) {
        guard let timeline = activeTimeline,
              index >= 0 && index < timeline.allClips.count else { return }
        selectClip(id: timeline.allClips[index].id)
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

        // CRITICAL FIX: Rebuild composition when trim point changes
        rebuildComposition()
        saveActiveTimeline()
    }

    /// Set the out point for the selected clip
    func setOutPoint(at time: Double) {
        guard let clip = selectedClip else { return }
        clip.setOutPointFromTime(time)

        // CRITICAL FIX: Rebuild composition when trim point changes
        rebuildComposition()
        saveActiveTimeline()
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
            if let (clip, _, timeInClip) = timeline.clip(at: clampedTime), let video = clip.videoItem {
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
              currentIndex < timeline.allClips.count - 1 else { return }

        selectClip(at: currentIndex + 1)
    }

    /// Navigate to the previous clip
    func goToPreviousClip() {
        guard let currentIndex = selectedClipIndex,
              currentIndex > 0 else { return }

        selectClip(at: currentIndex - 1)
    }
    
    // MARK: - In/Out Points (Phase 6)
    
    /// Set in point at current playhead position
    func setInPoint() {
        guard let timeline = activeTimeline else { return }
        timeline.inPoint = playheadTime
        saveActiveTimeline()
    }
    
    /// Set out point at current playhead position
    func setOutPoint() {
        guard let timeline = activeTimeline else { return }
        timeline.outPoint = playheadTime
        saveActiveTimeline()
    }
    
    /// Clear in point
    func clearInPoint() {
        guard let timeline = activeTimeline else { return }
        timeline.inPoint = nil
        saveActiveTimeline()
    }
    
    /// Clear out point
    func clearOutPoint() {
        guard let timeline = activeTimeline else { return }
        timeline.outPoint = nil
        saveActiveTimeline()
    }
    
    /// Clear both in and out points
    func clearInOutPoints() {
        guard let timeline = activeTimeline else { return }
        timeline.inPoint = nil
        timeline.outPoint = nil
        saveActiveTimeline()
    }
    
    /// Get export duration (respects in/out points if set)
    var exportDuration: Double {
        guard let timeline = activeTimeline else { return 0 }
        
        if let inPoint = timeline.inPoint, let outPoint = timeline.outPoint {
            return outPoint - inPoint
        }
        
        return timeline.totalDuration
    }

    // MARK: - Magnetic Snapping (Phase 8)
    
    /// Apply magnetic snapping to a time position
    /// Returns snapped time if within threshold, otherwise returns original time
    func applyMagneticSnapping(to time: Double) -> Double {
        guard magneticSnappingEnabled else { return time }
        guard let timeline = activeTimeline else { return time }
        
        var snapCandidates: [Double] = []
        
        // Add clip boundaries
        var currentTime: Double = 0
        for clip in timeline.allClips {
            snapCandidates.append(currentTime)  // Clip start
            currentTime += clip.trimmedDuration
            snapCandidates.append(currentTime)  // Clip end
        }
        
        // Add playhead position
        snapCandidates.append(playheadTime)
        
        // Add in/out points
        if let inPoint = timeline.inPoint {
            snapCandidates.append(inPoint)
        }
        if let outPoint = timeline.outPoint {
            snapCandidates.append(outPoint)
        }
        
        // Add timeline start/end
        snapCandidates.append(0)
        snapCandidates.append(timeline.totalDuration)
        
        // Find closest snap point
        let closest = snapCandidates.min(by: { abs($0 - time) < abs($1 - time) })
        
        if let snapPoint = closest, abs(snapPoint - time) <= snapThreshold {
            return snapPoint
        }
        
        return time
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
    
    // MARK: - Advanced Editing (Phase 10)
    
    /// Blade/split clip at current playhead position
    func bladeAtPlayhead() {
        guard let timeline = activeTimeline else { return }
        
        // Find which clip is at the playhead
        guard let (clip, _, timeInClip) = timeline.clip(at: playheadTime) else {
            print("⚠️ No clip at playhead position")
            return
        }
        
        // Split the clip
        if let newClip = TimelineEditingService.bladeClip(clip, at: timeInClip, in: timeline) {
            // Select the new clip
            selectClip(id: newClip.id)
            
            // Rebuild composition
            rebuildComposition()
            
            // Auto-save
            saveActiveTimeline()
        }
    }
    
    /// Ripple edit: Trim clip and shift subsequent clips
    func rippleEdit(clip: TimelineClip, newDuration: Double) {
        guard let timeline = activeTimeline else { return }
        
        TimelineEditingService.rippleEdit(clip: clip, newDuration: newDuration, in: timeline)
        
        rebuildComposition()
        saveActiveTimeline()
    }
    
    /// Roll edit: Trim two adjacent clips together
    func rollEdit(leftClip: TimelineClip, rightClip: TimelineClip, deltaTime: Double) {
        guard let timeline = activeTimeline else { return }
        
        TimelineEditingService.rollEdit(leftClip: leftClip, rightClip: rightClip, deltaTime: deltaTime, in: timeline)
        
        rebuildComposition()
        saveActiveTimeline()
    }
    
    /// Slip edit: Change source in/out without changing timeline duration
    func slipEdit(clip: TimelineClip, deltaTime: Double) {
        TimelineEditingService.slipEdit(clip: clip, deltaTime: deltaTime)
        
        rebuildComposition()
        saveActiveTimeline()
    }
    
    /// Slide edit: Move clip, adjacent clips adjust
    func slideEdit(clip: TimelineClip, deltaTime: Double) {
        guard let timeline = activeTimeline else { return }
        
        TimelineEditingService.slideEdit(clip: clip, deltaTime: deltaTime, in: timeline)
        
        rebuildComposition()
        saveActiveTimeline()
    }
}
