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
    @EnvironmentObject var timelineVM: TimelineViewModel
    @EnvironmentObject var projectVM: ProjectViewModel

    @State private var showingAddVideoPanel = false

    var body: some View {
        VStack(spacing: 6) {
            // Header
            HStack(alignment: .center, spacing: 8) {
                Text("Sequence")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()

                // Clip count badge
                if let timeline = timelineVM.timeline, !timeline.isEmpty {
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
            }
            .frame(height: 22)

            // Timeline track
            TimelineTrackNSViewWrapper(
                clips: timelineVM.timeline?.clips ?? [],
                transitions: timelineVM.timeline?.transitions ?? [],
                totalDuration: timelineVM.totalDuration,
                selectedClipID: timelineVM.selectedClipID,
                selectedTransitionID: timelineVM.selectedTransitionID,
                playheadTime: timelineVM.playheadTime,
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
                    if let clip = timelineVM.timeline?.clips.first(where: { $0.id == clipID }) {
                        clip.inPoint = inPoint
                        clip.outPoint = outPoint
                        timelineVM.objectWillChange.send()
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
                for url in urls {
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
}

// MARK: - NSViewRepresentable Wrapper

struct TimelineTrackNSViewWrapper: NSViewRepresentable {
    let clips: [TimelineClip]
    let transitions: [ClipTransition]
    let totalDuration: Double
    let selectedClipID: UUID?
    let selectedTransitionID: UUID?
    let playheadTime: Double

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

        // Clip thumbnail (if available and space permits)
        if width > 50, let thumbnail = clip.thumbnail {
            let thumbRect = NSRect(x: x + 4, y: 8, width: 28, height: clipHeight - 8)
            thumbnail.draw(in: thumbRect, from: .zero, operation: .sourceOver, fraction: 0.8)
        }

        // Clip name
        let textX = width > 50 ? x + 36 : x + 4
        let maxTextWidth = width - (width > 50 ? 44 : 8)
        if maxTextWidth > 20 {
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 10),
                .foregroundColor: isSelected ? NSColor.labelColor : NSColor.secondaryLabelColor
            ]
            let name = clip.displayName
            let truncated = truncateString(name, toWidth: maxTextWidth, attributes: attrs)
            truncated.draw(at: NSPoint(x: textX, y: 10), withAttributes: attrs)
        }

        // Duration label
        if width > 60 {
            let durationText = formatDuration(clip.trimmedDuration)
            let durationAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 9, weight: .regular),
                .foregroundColor: NSColor.tertiaryLabelColor
            ]
            let durationSize = durationText.size(withAttributes: durationAttrs)
            durationText.draw(at: NSPoint(x: x + width - durationSize.width - 4, y: clipHeight - 6), withAttributes: durationAttrs)
        }

        // Trim handles (when selected)
        if isSelected {
            drawTrimHandles(at: x, width: width)
        }
    }

    private func drawTrimHandles(at x: CGFloat, width: CGFloat) {
        let handleColor = NSColor.controlAccentColor.withAlphaComponent(0.8)
        handleColor.setFill()

        // Left handle
        let leftHandle = NSRect(x: x, y: 4, width: trimHandleWidth, height: clipHeight)
        let leftPath = NSBezierPath(roundedRect: leftHandle, xRadius: 3, yRadius: 3)
        leftPath.fill()

        // Right handle
        let rightHandle = NSRect(x: x + width - trimHandleWidth, y: 4, width: trimHandleWidth, height: clipHeight)
        let rightPath = NSBezierPath(roundedRect: rightHandle, xRadius: 3, yRadius: 3)
        rightPath.fill()
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
        if isTrimming, let clipIndex = trimmingClipIndex {
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

    private func handleTrimDrag(point: NSPoint, clipIndex: Int) {
        guard clipIndex < clips.count else { return }
        let clip = clips[clipIndex]

        let availableWidth = bounds.width - addButtonWidth
        var currentX: CGFloat = 0
        for i in 0..<clipIndex {
            currentX += CGFloat(clips[i].trimmedDuration / totalDuration) * availableWidth
        }

        let clipWidth = CGFloat(clip.trimmedDuration / totalDuration) * availableWidth
        let clipSourceDuration = clip.sourceDuration

        switch trimmingEdge {
        case .left:
            // Calculate new in point
            let deltaX = point.x - currentX
            let deltaNormalized = (deltaX / availableWidth) * totalDuration / clipSourceDuration
            let newInPoint = max(0, min(clip.outPoint - 0.05, trimStartValue + deltaNormalized))
            delegate?.trackDidTrimClip(clip.id, inPoint: newInPoint, outPoint: clip.outPoint)

        case .right:
            // Calculate new out point
            let deltaX = point.x - (currentX + clipWidth)
            let deltaNormalized = (deltaX / availableWidth) * totalDuration / clipSourceDuration
            let newOutPoint = max(clip.inPoint + 0.05, min(1.0, trimStartValue + deltaNormalized))
            delegate?.trackDidTrimClip(clip.id, inPoint: clip.inPoint, outPoint: newOutPoint)

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
        .environmentObject(TimelineViewModel())
        .environmentObject(ProjectViewModel())
        .frame(width: 600, height: 80)
        .padding()
}
