//
//  TimelineTrackView.swift
//  cropaway
//

import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

/// SwiftUI container for the timeline track with header and controls
struct TimelineTrackView: View {
    @Environment(TimelineViewModel.self) private var timelineVM: TimelineViewModel
    @Environment(ProjectViewModel.self) private var projectVM: ProjectViewModel
    @Environment(ExportViewModel.self) private var exportVM: ExportViewModel

    @State private var showingAddVideoPanel = false
    @State private var clipRefreshTrigger: Int = 0
    @State private var clipObservers: [UUID: AnyCancellable] = [:]

    var body: some View {
        VStack(spacing: 6) {
            // Header
            HStack(alignment: .center, spacing: 8) {
                Text(timelineVM.activeTimeline?.name ?? "Sequence")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()

                // Clip count badge
                if let timeline = timelineVM.activeTimeline, !timeline.isEmpty {
                    Text("\(timeline.clipCount) clips")
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.1))
                        .clipShape(Capsule())
                }

                // Add clip button
                Button(action: { showingAddVideoPanel = true }) {
                    Image(systemName: "plus.rectangle.on.rectangle")
                        .font(.system(size: 11))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .help("Add video to sequence")

                // Remove selected clip button
                if timelineVM.selectedClipID != nil {
                    Button(action: { timelineVM.removeSelectedClip() }) {
                        Image(systemName: "minus.rectangle")
                            .font(.system(size: 11))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .help("Remove selected clip")
                }

                // Export timeline button
                if let timeline = timelineVM.activeTimeline, !timeline.isEmpty {
                    Button(action: {
                        Task {
                            await exportVM.exportTimeline(timeline, suggestedName: timeline.name)
                        }
                    }) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 11))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .help("Export timeline as video")
                    .disabled(exportVM.isExporting)
                }
            }
            .frame(height: 22)

            // Timeline track
            TimelineTrackNSViewWrapper(
                clips: timelineVM.activeTimeline?.clips ?? [],
                transitions: timelineVM.activeTimeline?.transitions ?? [],
                totalDuration: timelineVM.totalDuration,
                selectedClipID: timelineVM.selectedClipID,
                selectedTransitionID: timelineVM.selectedTransitionID,
                playheadTime: timelineVM.playheadTime,
                refreshTrigger: clipRefreshTrigger,
                onSelectClip: { clipID in
                    timelineVM.selectClip(id: clipID)
                },
                onSelectTransition: { transitionID in
                    timelineVM.selectTransition(id: transitionID)
                },
                onSeek: { time in
                    timelineVM.seek(to: time)
                },
                onReorderClip: { from, to in
                    timelineVM.reorderClip(from: from, to: to)
                },
                onTrimClip: { clipID, inPoint, outPoint in
                    Task { @MainActor in
                        if let clip = timelineVM.activeTimeline?.clips.first(where: { $0.id == clipID }) {
                            clip.inPoint = inPoint
                            clip.outPoint = outPoint
                            // Rebuild composition with new trim points
                            timelineVM.rebuildComposition()
                            // Auto-save timeline
                            timelineVM.saveActiveTimeline()
                        }
                    }
                },
                onAddClipAtEnd: {
                    showingAddVideoPanel = true
                },
                onDropVideo: { video, index in
                    timelineVM.handleVideoDrop(video, at: index)
                }
            )
            .frame(height: 48)
            .focusable()
            .onAppear {
                setupClipObservers()
            }
            .onChange(of: timelineVM.activeTimeline?.clips.map { $0.id }) { _, _ in
                setupClipObservers()
            }

            // Hints
            if timelineVM.timeline?.isEmpty ?? true {
                Text("Drag videos here or click + to add clips")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            } else if timelineVM.selectedClipID != nil {
                Text("Drag edges to trim \u{2022} Drag clip to reorder \u{2022} Click transition to edit")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .fileImporter(
            isPresented: $showingAddVideoPanel,
            allowedContentTypes: [.movie, .video, .quickTimeMovie, .mpeg4Movie],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                for _ in urls {
                    // Create VideoItem and add to timeline
                    // The projectVM will handle this
                    Task {
                        await projectVM.addVideos(from: urls)
                        // Add the last added videos to the sequence
                        for video in projectVM.videos.suffix(urls.count) {
                            timelineVM.addClip(from: video)
                        }
                    }
                }
            case .failure:
                break
            }
        }
    }
    
    // MARK: - Clip Observers
    
    /// Set up observers for clip thumbnail changes to trigger view updates
    private func setupClipObservers() {
        guard let clips = timelineVM.activeTimeline?.clips else { return }
        
        // Remove observers for clips that no longer exist
        let currentClipIDs = Set(clips.map { $0.id })
        clipObservers = clipObservers.filter { currentClipIDs.contains($0.key) }
        
        // Add observers for new clips
        for clip in clips {
            guard clipObservers[clip.id] == nil else { continue }
            
            let observer = clip.$thumbnailStrip
                .sink { [weak clip] _ in
                    guard clip != nil else { return }
                    Task { @MainActor in
                        clipRefreshTrigger += 1
                    }
                }
            
            clipObservers[clip.id] = observer
        }
    }
}

// MARK: - NSViewRepresentable Wrapper

struct TimelineTrackNSViewWrapper: NSViewRepresentable {
    let clips: [TimelineClip]
    let transitions: [ClipTransition]
    let totalDuration: Double
    let selectedClipID: UUID?
    let selectedTransitionID: UUID?
    let playheadTime: Double
    let refreshTrigger: Int  // Forces view updates when clip properties change

    let onSelectClip: (UUID) -> Void
    let onSelectTransition: (UUID) -> Void
    let onSeek: (Double) -> Void
    let onReorderClip: (Int, Int) -> Void
    let onTrimClip: (UUID, Double, Double) -> Void
    let onAddClipAtEnd: () -> Void
    let onDropVideo: (VideoItem, Int?) -> Void

    func makeNSView(context: Context) -> TimelineTrackNSView {
        let view = TimelineTrackNSView()
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ nsView: TimelineTrackNSView, context: Context) {
        nsView.clips = clips
        nsView.transitions = transitions
        nsView.totalDuration = totalDuration
        nsView.selectedClipID = selectedClipID
        nsView.selectedTransitionID = selectedTransitionID
        nsView.playheadTime = playheadTime
        nsView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, TimelineTrackDelegate {
        var parent: TimelineTrackNSViewWrapper

        init(_ parent: TimelineTrackNSViewWrapper) {
            self.parent = parent
        }

        func trackDidSelectClip(_ clipID: UUID) {
            parent.onSelectClip(clipID)
        }

        func trackDidSelectTransition(_ transitionID: UUID) {
            parent.onSelectTransition(transitionID)
        }

        func trackDidSeek(to time: Double) {
            parent.onSeek(time)
        }

        func trackDidReorderClip(from: Int, to: Int) {
            parent.onReorderClip(from, to)
        }

        func trackDidTrimClip(_ clipID: UUID, inPoint: Double, outPoint: Double) {
            parent.onTrimClip(clipID, inPoint, outPoint)
        }

        func trackDidRequestAddClip() {
            parent.onAddClipAtEnd()
        }

        func trackDidDropVideo(_ video: VideoItem, at index: Int?) {
            parent.onDropVideo(video, index)
        }
    }
}

// MARK: - Delegate Protocol

protocol TimelineTrackDelegate: AnyObject {
    func trackDidSelectClip(_ clipID: UUID)
    func trackDidSelectTransition(_ transitionID: UUID)
    func trackDidSeek(to time: Double)
    func trackDidReorderClip(from: Int, to: Int)
    func trackDidTrimClip(_ clipID: UUID, inPoint: Double, outPoint: Double)
    func trackDidRequestAddClip()
    func trackDidDropVideo(_ video: VideoItem, at index: Int?)
}

// MARK: - NSView Implementation

class TimelineTrackNSView: NSView {
    weak var delegate: TimelineTrackDelegate?

    var clips: [TimelineClip] = []
    var transitions: [ClipTransition] = []
    var totalDuration: Double = 0
    var selectedClipID: UUID?
    var selectedTransitionID: UUID?
    var playheadTime: Double = 0

    // Interaction state
    private var isDraggingClip = false
    private var draggingClipIndex: Int?
    private var dragStartX: CGFloat = 0
    private var dragCurrentX: CGFloat = 0

    private var isTrimming = false
    private var trimmingClipIndex: Int?
    private var trimmingEdge: TrimEdge = .none
    private var trimStartValue: Double = 0
    private var lastTrimTime: TimeInterval = 0
    private let minTrimInterval: TimeInterval = 0.033 // ~30fps

    private var isScrubbing = false

    private var clickCount = 0
    private var lastClickTime: Date?

    // Layout constants
    private let clipHeight: CGFloat = 40
    private let clipCornerRadius: CGFloat = 6
    private let transitionWidth: CGFloat = 24
    private let trimHandleWidth: CGFloat = 8
    private let addButtonWidth: CGFloat = 32
    private let playheadWidth: CGFloat = 2

    private enum TrimEdge {
        case none, left, right
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let rect = bounds

        // Background track
        NSColor.labelColor.withAlphaComponent(0.05).setFill()
        let trackPath = NSBezierPath(roundedRect: rect.insetBy(dx: 0, dy: 4), xRadius: 8, yRadius: 8)
        trackPath.fill()

        guard totalDuration > 0 else {
            drawEmptyState(in: rect)
            return
        }

        // Calculate layout
        let availableWidth = rect.width - addButtonWidth
        var currentX: CGFloat = 0

        // Draw clips and transitions
        for (index, clip) in clips.enumerated() {
            let clipWidth = CGFloat(clip.trimmedDuration / totalDuration) * availableWidth

            // Draw clip
            drawClip(clip, at: currentX, width: clipWidth, index: index)

            currentX += clipWidth

            // Draw transition indicator if not the last clip
            if index < clips.count - 1 {
                if let transition = transitions.first(where: { $0.afterClipIndex == index }) {
                    drawTransition(transition, at: currentX - transitionWidth / 2)
                }
            }
        }

        // Draw add button at the end
        drawAddButton(at: currentX)

        // Draw playhead
        drawPlayhead(in: rect, availableWidth: availableWidth)
    }

    private func drawEmptyState(in rect: NSRect) {
        // Draw placeholder text
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11),
            .foregroundColor: NSColor.tertiaryLabelColor
        ]
        let text = "Drop videos here to create a sequence"
        let size = text.size(withAttributes: attrs)
        let point = NSPoint(x: (rect.width - size.width) / 2, y: (rect.height - size.height) / 2)
        text.draw(at: point, withAttributes: attrs)

        // Draw add button
        drawAddButton(at: rect.width - addButtonWidth)
    }

    private func drawClip(_ clip: TimelineClip, at x: CGFloat, width: CGFloat, index: Int) {
        let clipRect = NSRect(x: x, y: 4, width: width, height: clipHeight)
        let isSelected = clip.id == selectedClipID
        let isTrimmed = clip.isTrimmed

        // Clip background
        let bgColor: NSColor
        if isDraggingClip && draggingClipIndex == index {
            bgColor = NSColor.controlAccentColor.withAlphaComponent(0.6)
        } else if isSelected {
            bgColor = NSColor.controlAccentColor.withAlphaComponent(0.3)
        } else {
            bgColor = NSColor.labelColor.withAlphaComponent(0.1)
        }

        bgColor.setFill()
        let clipPath = NSBezierPath(roundedRect: clipRect, xRadius: clipCornerRadius, yRadius: clipCornerRadius)
        clipPath.fill()

        // Clip border
        if isSelected {
            NSColor.controlAccentColor.setStroke()
            clipPath.lineWidth = 2
            clipPath.stroke()
        }

        // Clip thumbnail strip (if available and space permits)
        if width > 50 {
            if !clip.thumbnailStrip.isEmpty {
                // Draw filmstrip-style thumbnails
                let thumbHeight = clipHeight - 8
                let thumbWidth = thumbHeight * 4.0 / 3.0 // 4:3 aspect ratio
                let thumbnailsAvailable = clip.thumbnailStrip.count
                let thumbnailsNeeded = Int(ceil((width - 8) / thumbWidth))
                
                var currentX = x + 4
                for i in 0..<thumbnailsNeeded {
                    guard currentX + thumbWidth <= x + width - 4 else { break }
                    
                    // Repeat thumbnails if we need more than we have
                    let thumbIndex = i % thumbnailsAvailable
                    let thumbnail = clip.thumbnailStrip[thumbIndex]
                    
                    let thumbRect = NSRect(x: currentX, y: 8, width: thumbWidth, height: thumbHeight)
                    thumbnail.draw(in: thumbRect, from: .zero, operation: .sourceOver, fraction: 0.8)
                    
                    // Draw subtle border between thumbnails
                    if i < thumbnailsNeeded - 1 {
                        NSColor.separatorColor.withAlphaComponent(0.3).setStroke()
                        let borderPath = NSBezierPath()
                        borderPath.move(to: NSPoint(x: currentX + thumbWidth, y: 8))
                        borderPath.line(to: NSPoint(x: currentX + thumbWidth, y: 8 + thumbHeight))
                        borderPath.lineWidth = 0.5
                        borderPath.stroke()
                    }
                    
                    currentX += thumbWidth
                }
            } else if let thumbnail = clip.thumbnail {
                // Fallback to single thumbnail if strip not ready yet
                let thumbRect = NSRect(x: x + 4, y: 8, width: 28, height: clipHeight - 8)
                thumbnail.draw(in: thumbRect, from: .zero, operation: .sourceOver, fraction: 0.8)
            }
        }

        // Clip name (draw as overlay with background)
        if width > 60 {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            let name = clip.displayName
            let nameSize = name.size(withAttributes: attrs)
            let padding: CGFloat = 4
            let nameBgRect = NSRect(
                x: x + 4,
                y: 8,
                width: min(nameSize.width + padding * 2, width - 8),
                height: nameSize.height + padding
            )
            
            // Semi-transparent background
            NSColor.black.withAlphaComponent(0.6).setFill()
            let bgPath = NSBezierPath(roundedRect: nameBgRect, xRadius: 3, yRadius: 3)
            bgPath.fill()
            
            // Draw text
            let maxTextWidth = width - 16
            let truncated = truncateString(name, toWidth: maxTextWidth, attributes: attrs)
            truncated.draw(at: NSPoint(x: x + 4 + padding, y: 10), withAttributes: attrs)
        }

        // Duration label (draw as overlay)
        if width > 80 {
            let durationText = formatDuration(clip.trimmedDuration)
            let durationAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium),
                .foregroundColor: NSColor.white
            ]
            let durationSize = durationText.size(withAttributes: durationAttrs)
            let padding: CGFloat = 3
            let durationBgRect = NSRect(
                x: x + width - durationSize.width - padding * 2 - 4,
                y: clipHeight - durationSize.height - padding - 4,
                width: durationSize.width + padding * 2,
                height: durationSize.height + padding
            )
            
            // Semi-transparent background
            NSColor.black.withAlphaComponent(0.6).setFill()
            let bgPath = NSBezierPath(roundedRect: durationBgRect, xRadius: 3, yRadius: 3)
            bgPath.fill()
            
            // Draw text
            durationText.draw(at: NSPoint(x: x + width - durationSize.width - padding - 4, y: clipHeight - durationSize.height - 4), withAttributes: durationAttrs)
        }

        // Draw trimmed regions if clip is trimmed (like NLEs)
        if isTrimmed {
            drawTrimmedRegions(clip: clip, at: x, width: width)
        }
        
        // Trim handles (when selected)
        if isSelected {
            drawTrimHandles(at: x, width: width, clip: clip)
        }
    }

    private func drawTrimmedRegions(clip: TimelineClip, at x: CGFloat, width: CGFloat) {
        // Draw visual indicators at the edges to show trim state (like NLEs)
        let indicatorWidth: CGFloat = 3
        let indicatorColor = NSColor.systemYellow.withAlphaComponent(0.6)
        
        // Left trim indicator (if trimmed from start)
        if clip.inPoint > 0.001 {
            let leftIndicator = NSRect(x: x + 1, y: 4 + 1, width: indicatorWidth, height: clipHeight - 2)
            indicatorColor.setFill()
            NSBezierPath(rect: leftIndicator).fill()
            
            // Add small bracket
            NSColor.systemYellow.setStroke()
            let bracket = NSBezierPath()
            bracket.move(to: NSPoint(x: x + indicatorWidth + 2, y: 4 + 4))
            bracket.line(to: NSPoint(x: x + 2, y: 4 + 4))
            bracket.line(to: NSPoint(x: x + 2, y: 4 + clipHeight - 4))
            bracket.line(to: NSPoint(x: x + indicatorWidth + 2, y: 4 + clipHeight - 4))
            bracket.lineWidth = 1
            bracket.stroke()
        }
        
        // Right trim indicator (if trimmed from end)
        if clip.outPoint < 0.999 {
            let rightIndicator = NSRect(x: x + width - indicatorWidth - 1, y: 4 + 1, width: indicatorWidth, height: clipHeight - 2)
            indicatorColor.setFill()
            NSBezierPath(rect: rightIndicator).fill()
            
            // Add small bracket
            NSColor.systemYellow.setStroke()
            let bracket = NSBezierPath()
            bracket.move(to: NSPoint(x: x + width - indicatorWidth - 2, y: 4 + 4))
            bracket.line(to: NSPoint(x: x + width - 2, y: 4 + 4))
            bracket.line(to: NSPoint(x: x + width - 2, y: 4 + clipHeight - 4))
            bracket.line(to: NSPoint(x: x + width - indicatorWidth - 2, y: 4 + clipHeight - 4))
            bracket.lineWidth = 1
            bracket.stroke()
        }
    }
    
    private func drawTrimHandles(at x: CGFloat, width: CGFloat, clip: TimelineClip) {
        let handleColor = NSColor.controlAccentColor
        let handleWidth: CGFloat = 6
        let handleHeight = clipHeight
        
        // Draw left trim handle
        handleColor.setFill()
        let leftHandle = NSRect(x: x, y: 4, width: handleWidth, height: handleHeight)
        NSBezierPath(roundedRect: leftHandle, xRadius: 2, yRadius: 2).fill()
        
        // Draw grip lines on left handle
        NSColor.white.withAlphaComponent(0.8).setStroke()
        for i in 0..<3 {
            let lineX = x + 2 + CGFloat(i) * 1.5
            let linePath = NSBezierPath()
            linePath.move(to: NSPoint(x: lineX, y: 4 + 8))
            linePath.line(to: NSPoint(x: lineX, y: 4 + handleHeight - 8))
            linePath.lineWidth = 0.5
            linePath.stroke()
        }
        
        // Draw right trim handle
        handleColor.setFill()
        let rightHandle = NSRect(x: x + width - handleWidth, y: 4, width: handleWidth, height: handleHeight)
        NSBezierPath(roundedRect: rightHandle, xRadius: 2, yRadius: 2).fill()
        
        // Draw grip lines on right handle
        NSColor.white.withAlphaComponent(0.8).setStroke()
        for i in 0..<3 {
            let lineX = x + width - handleWidth + 2 + CGFloat(i) * 1.5
            let linePath = NSBezierPath()
            linePath.move(to: NSPoint(x: lineX, y: 4 + 8))
            linePath.line(to: NSPoint(x: lineX, y: 4 + handleHeight - 8))
            linePath.lineWidth = 0.5
            linePath.stroke()
        }
    }

    private func drawTransition(_ transition: ClipTransition, at x: CGFloat) {
        let isSelected = transition.id == selectedTransitionID
        let centerY = clipHeight / 2 + 4

        // Diamond shape for transition
        let size: CGFloat = isSelected ? 14 : 12
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x, y: centerY - size/2))
        path.line(to: NSPoint(x: x + size/2, y: centerY))
        path.line(to: NSPoint(x: x, y: centerY + size/2))
        path.line(to: NSPoint(x: x - size/2, y: centerY))
        path.close()

        // Color based on type and selection
        let fillColor: NSColor
        switch transition.type {
        case .cut:
            fillColor = isSelected ? NSColor.systemOrange : NSColor.labelColor.withAlphaComponent(0.4)
        case .opticalFlow:
            fillColor = isSelected ? NSColor.systemPurple : NSColor.systemPurple.withAlphaComponent(0.6)
        }

        fillColor.setFill()
        path.fill()

        if isSelected {
            NSColor.white.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        }
    }

    private func drawAddButton(at x: CGFloat) {
        let buttonRect = NSRect(x: x + 4, y: 8, width: addButtonWidth - 8, height: clipHeight - 8)

        // Button background
        NSColor.labelColor.withAlphaComponent(0.05).setFill()
        let buttonPath = NSBezierPath(roundedRect: buttonRect, xRadius: 4, yRadius: 4)
        buttonPath.fill()

        // Plus icon
        let plusColor = NSColor.secondaryLabelColor
        plusColor.setStroke()

        let centerX = x + addButtonWidth / 2
        let centerY = clipHeight / 2 + 4
        let plusSize: CGFloat = 10

        let plusPath = NSBezierPath()
        plusPath.move(to: NSPoint(x: centerX - plusSize/2, y: centerY))
        plusPath.line(to: NSPoint(x: centerX + plusSize/2, y: centerY))
        plusPath.move(to: NSPoint(x: centerX, y: centerY - plusSize/2))
        plusPath.line(to: NSPoint(x: centerX, y: centerY + plusSize/2))
        plusPath.lineWidth = 2
        plusPath.lineCapStyle = .round
        plusPath.stroke()
    }

    private func drawPlayhead(in rect: NSRect, availableWidth: CGFloat) {
        guard totalDuration > 0 else { return }

        let playheadX = CGFloat(playheadTime / totalDuration) * availableWidth

        NSColor.red.setFill()
        NSColor.red.setStroke()

        // Triangle at top
        let trianglePath = NSBezierPath()
        trianglePath.move(to: NSPoint(x: playheadX - 5, y: 0))
        trianglePath.line(to: NSPoint(x: playheadX + 5, y: 0))
        trianglePath.line(to: NSPoint(x: playheadX, y: 6))
        trianglePath.close()
        trianglePath.fill()

        // Vertical line
        let linePath = NSBezierPath()
        linePath.move(to: NSPoint(x: playheadX, y: 6))
        linePath.line(to: NSPoint(x: playheadX, y: rect.height))
        linePath.lineWidth = playheadWidth
        linePath.stroke()
    }

    // MARK: - Helper Methods

    private func truncateString(_ string: String, toWidth width: CGFloat, attributes: [NSAttributedString.Key: Any]) -> String {
        var truncated = string
        while truncated.count > 1 && (truncated + "...").size(withAttributes: attributes).width > width {
            truncated = String(truncated.dropLast())
        }
        return truncated == string ? string : truncated + "..."
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let frames = Int((seconds.truncatingRemainder(dividingBy: 1)) * 30)
        return String(format: "%d:%02d:%02d", mins, secs, frames)
    }

    // MARK: - Hit Testing

    private func clipAt(_ point: NSPoint) -> (clip: TimelineClip, index: Int)? {
        guard totalDuration > 0 else { return nil }

        let availableWidth = bounds.width - addButtonWidth
        var currentX: CGFloat = 0

        for (index, clip) in clips.enumerated() {
            let clipWidth = CGFloat(clip.trimmedDuration / totalDuration) * availableWidth

            if point.x >= currentX && point.x < currentX + clipWidth && point.y >= 4 && point.y <= 4 + clipHeight {
                return (clip, index)
            }

            currentX += clipWidth
        }

        return nil
    }

    private func trimEdgeAt(_ point: NSPoint) -> (clipIndex: Int, edge: TrimEdge)? {
        guard totalDuration > 0, let selectedID = selectedClipID else { return nil }

        let availableWidth = bounds.width - addButtonWidth
        var currentX: CGFloat = 0

        for (index, clip) in clips.enumerated() {
            let clipWidth = CGFloat(clip.trimmedDuration / totalDuration) * availableWidth

            if clip.id == selectedID {
                // Check left edge
                if point.x >= currentX && point.x < currentX + trimHandleWidth {
                    return (index, .left)
                }
                // Check right edge
                if point.x >= currentX + clipWidth - trimHandleWidth && point.x < currentX + clipWidth {
                    return (index, .right)
                }
            }

            currentX += clipWidth
        }

        return nil
    }

    private func transitionAt(_ point: NSPoint) -> ClipTransition? {
        guard totalDuration > 0 else { return nil }

        let availableWidth = bounds.width - addButtonWidth
        var currentX: CGFloat = 0

        for (index, clip) in clips.enumerated() {
            let clipWidth = CGFloat(clip.trimmedDuration / totalDuration) * availableWidth
            currentX += clipWidth

            if index < clips.count - 1 {
                let transitionCenter = currentX
                if abs(point.x - transitionCenter) < transitionWidth / 2 {
                    return transitions.first { $0.afterClipIndex == index }
                }
            }
        }

        return nil
    }

    private func isAddButtonAt(_ point: NSPoint) -> Bool {
        let availableWidth = bounds.width - addButtonWidth
        return point.x >= availableWidth
    }

    private func timeAtX(_ x: CGFloat) -> Double {
        guard totalDuration > 0 else { return 0 }
        let availableWidth = bounds.width - addButtonWidth
        let fraction = max(0, min(1, x / availableWidth))
        return fraction * totalDuration
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)

        // Track double-click
        let now = Date()
        if let lastClick = lastClickTime, now.timeIntervalSince(lastClick) < 0.3 {
            clickCount += 1
        } else {
            clickCount = 1
        }
        lastClickTime = now

        // Check add button
        if isAddButtonAt(point) {
            delegate?.trackDidRequestAddClip()
            return
        }

        // Check trim handles first (for selected clip)
        if let trimInfo = trimEdgeAt(point) {
            isTrimming = true
            trimmingClipIndex = trimInfo.clipIndex
            trimmingEdge = trimInfo.edge
            let clip = clips[trimInfo.clipIndex]
            trimStartValue = trimInfo.edge == .left ? clip.inPoint : clip.outPoint
            return
        }

        // Check transition
        if let transition = transitionAt(point) {
            delegate?.trackDidSelectTransition(transition.id)
            return
        }

        // Check clip
        if let (clip, index) = clipAt(point) {
            if clickCount >= 2 {
                // Double-click: could open trim editor or something
                clickCount = 0
            } else {
                delegate?.trackDidSelectClip(clip.id)

                // Start drag for reorder
                isDraggingClip = true
                draggingClipIndex = index
                dragStartX = point.x
                dragCurrentX = point.x
            }
            return
        }

        // Click on empty area - scrub
        isScrubbing = true
        let time = timeAtX(point.x)
        delegate?.trackDidSeek(to: time)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if isTrimming, let clipIndex = trimmingClipIndex {
            handleTrimDrag(point: point, clipIndex: clipIndex)
        } else if isDraggingClip {
            dragCurrentX = point.x
            needsDisplay = true
        } else if isScrubbing {
            let time = timeAtX(point.x)
            delegate?.trackDidSeek(to: time)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isTrimming, let _ = trimmingClipIndex {
            isTrimming = false
            trimmingClipIndex = nil
            trimmingEdge = .none
        } else if isDraggingClip, let fromIndex = draggingClipIndex {
            // Calculate destination index based on drop position
            let point = convert(event.locationInWindow, from: nil)
            if let (_, toIndex) = clipAt(point), toIndex != fromIndex {
                delegate?.trackDidReorderClip(from: fromIndex, to: toIndex)
            }
            isDraggingClip = false
            draggingClipIndex = nil
        }

        isScrubbing = false
        needsDisplay = true
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        // Remove existing tracking areas
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        
        // Add tracking area for cursor updates
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .mouseMoved, .mouseEnteredAndExited],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
    
    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        
        // Check if hovering over trim handle
        if let trimInfo = trimEdgeAt(point) {
            NSCursor.resizeLeftRight.set()
            
            // Set tooltip showing trim percentage
            let clip = clips[trimInfo.clipIndex]
            let percentage = Int((trimInfo.edge == .left ? clip.inPoint : clip.outPoint) * 100)
            toolTip = "Trim \(trimInfo.edge == .left ? "In" : "Out"): \(percentage)%"
        } else {
            NSCursor.arrow.set()
            toolTip = nil
        }
    }
    
    override func mouseExited(with event: NSEvent) {
        NSCursor.arrow.set()
    }

    private func handleTrimDrag(point: NSPoint, clipIndex: Int) {
        guard clipIndex >= 0 && clipIndex < clips.count else { return }
        let clip = clips[clipIndex]

        guard trimmingEdge != .none else { return }

        let availableWidth = bounds.width - addButtonWidth

        // Calculate clip's current position and width
        var currentX: CGFloat = 0
        for i in 0..<clipIndex {
            currentX += CGFloat(clips[i].trimmedDuration / totalDuration) * availableWidth
        }

        // CRITICAL FIX: Use clip's current (potentially changed) trimmed duration
        let clipWidth = CGFloat(clip.trimmedDuration / totalDuration) * availableWidth

        // Get clip's source duration
        let clipSourceDuration = clip.videoItem?.metadata.duration ?? 1.0
        guard clipSourceDuration > 0 else { return }

        // Throttle updates
        let now = Date().timeIntervalSince1970
        let shouldUpdate = now - lastTrimTime >= minTrimInterval

        switch trimmingEdge {
        case .left:
            // FIXED: Calculate delta relative to THIS clip's width, not entire timeline
            let deltaX = point.x - currentX
            let deltaAsClipFraction = deltaX / clipWidth  // Fraction of THIS clip
            let deltaInSourceTime = deltaAsClipFraction * clip.trimmedDuration  // Delta in seconds
            let deltaNormalized = deltaInSourceTime / clipSourceDuration  // Normalize to 0-1

            let newInPoint = max(0, min(clip.outPoint - 0.01, trimStartValue + deltaNormalized))

            #if DEBUG
            print("🔧 Trim Left - Clip \(clipIndex):")
            print("  Point.x: \(point.x), CurrentX: \(currentX)")
            print("  ClipWidth: \(clipWidth), DeltaX: \(deltaX)")
            print("  DeltaAsClipFraction: \(deltaAsClipFraction)")
            print("  DeltaInSourceTime: \(deltaInSourceTime)s")
            print("  DeltaNormalized: \(deltaNormalized)")
            print("  New InPoint: \(newInPoint)")
            #endif

            if shouldUpdate {
                delegate?.trackDidTrimClip(clip.id, inPoint: newInPoint, outPoint: clip.outPoint)
                lastTrimTime = now
            }

        case .right:
            // FIXED: Calculate delta relative to THIS clip's width
            let deltaX = point.x - (currentX + clipWidth)
            let deltaAsClipFraction = deltaX / clipWidth
            let deltaInSourceTime = deltaAsClipFraction * clip.trimmedDuration
            let deltaNormalized = deltaInSourceTime / clipSourceDuration

            let newOutPoint = max(clip.inPoint + 0.01, min(1.0, trimStartValue + deltaNormalized))

            #if DEBUG
            print("🔧 Trim Right - Clip \(clipIndex):")
            print("  Point.x: \(point.x), CurrentX: \(currentX)")
            print("  ClipWidth: \(clipWidth), DeltaX: \(deltaX)")
            print("  DeltaAsClipFraction: \(deltaAsClipFraction)")
            print("  DeltaInSourceTime: \(deltaInSourceTime)s")
            print("  DeltaNormalized: \(deltaNormalized)")
            print("  New OutPoint: \(newOutPoint)")
            #endif

            if shouldUpdate {
                delegate?.trackDidTrimClip(clip.id, inPoint: clip.inPoint, outPoint: newOutPoint)
                lastTrimTime = now
            }

        case .none:
            break
        }

        needsDisplay = true
    }

    // MARK: - Drag and Drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let items = sender.draggingPasteboard.pasteboardItems else { return false }

        for item in items {
            if let urlString = item.string(forType: .fileURL),
               let url = URL(string: urlString) {
                // Check if it's a video file
                let validExtensions = ["mov", "mp4", "m4v", "avi", "mkv", "webm"]
                if validExtensions.contains(url.pathExtension.lowercased()) {
                    // Create a VideoItem - this would need to be handled by the delegate
                    // For now, just return true to indicate success
                    return true
                }
            }
        }

        return false
    }
}

// MARK: - Preview

#Preview {
    TimelineTrackView()
        .environment(TimelineViewModel())
        .environment(ProjectViewModel())
        .frame(width: 600, height: 80)
        .padding()
}
