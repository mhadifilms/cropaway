//
//  KeyframeTimelineView.swift
//  cropaway
//

import SwiftUI
import AppKit

struct KeyframeTimelineView: View {
    @EnvironmentObject var playerVM: VideoPlayerViewModel
    @EnvironmentObject var keyframeVM: KeyframeViewModel

    @State private var draggedKeyframe: Keyframe? = nil
    @State private var dragOffset: CGFloat = 0
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            // Header
            HStack(alignment: .center, spacing: 8) {
                Text("Keyframes")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()

                // Selection count
                if keyframeVM.selectedKeyframeIDs.count > 1 {
                    Text("\(keyframeVM.selectedKeyframeIDs.count) selected")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                // Keyframe count badge
                if !keyframeVM.keyframes.isEmpty {
                    Text("\(keyframeVM.keyframes.count)")
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.1))
                        .clipShape(Capsule())
                }

                Button(action: { keyframeVM.addKeyframe(at: playerVM.currentTime) }) {
                    Image(systemName: "plus.diamond")
                        .font(.system(size: 11))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .help("Add keyframe (⌘K)")

                if !keyframeVM.selectedKeyframeIDs.isEmpty {
                    Button(action: { keyframeVM.deleteSelected() }) {
                        Image(systemName: "minus.diamond")
                            .font(.system(size: 11))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete selected (⌫)")
                }
            }
            .frame(height: 22)

            // Timeline track
            KeyframeTrackView(
                keyframes: keyframeVM.keyframes,
                selectedIDs: keyframeVM.selectedKeyframeIDs,
                duration: playerVM.duration,
                draggedKeyframe: $draggedKeyframe,
                dragOffset: $dragOffset,
                currentTime: playerVM.currentTime,
                onSelect: { keyframe, extend in
                    keyframeVM.selectKeyframe(keyframe, extending: extend)
                    playerVM.seek(to: keyframe.timestamp)
                },
                onSeek: { time in
                    keyframeVM.deselectAll()
                    playerVM.seek(to: time)
                },
                onMove: { keyframe, newTime in
                    keyframeVM.moveKeyframe(keyframe, to: newTime)
                    playerVM.seek(to: keyframe.timestamp)
                },
                onDelete: { keyframe in
                    keyframeVM.removeKeyframe(keyframe)
                },
                onAddKeyframe: { time in
                    keyframeVM.addKeyframe(at: time)
                }
            )
            .frame(height: 32)
            .focusable()
            .focused($isFocused)
            .onDeleteCommand {
                keyframeVM.deleteSelected()
            }
            .onKeyPress(.delete) {
                keyframeVM.deleteSelected()
                return .handled
            }
            .onKeyPress(.deleteForward) {
                keyframeVM.deleteSelected()
                return .handled
            }

            // Hints
            if keyframeVM.keyframes.isEmpty {
                Text("Click + or double-click timeline to add keyframes")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            } else if keyframeVM.keyframes.count == 1 {
                Text("Add another keyframe to enable animation")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            } else if !keyframeVM.selectedKeyframeIDs.isEmpty {
                Text("⌫ Delete • Drag to move • Shift+click for multi-select")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - Track View (NSViewRepresentable for proper mouse handling)

struct KeyframeTrackView: NSViewRepresentable {
    let keyframes: [Keyframe]
    let selectedIDs: Set<UUID>
    let duration: Double
    @Binding var draggedKeyframe: Keyframe?
    @Binding var dragOffset: CGFloat
    let currentTime: Double

    let onSelect: (Keyframe, Bool) -> Void
    let onSeek: (Double) -> Void
    let onMove: (Keyframe, Double) -> Void
    let onDelete: (Keyframe) -> Void
    let onAddKeyframe: (Double) -> Void

    func makeNSView(context: Context) -> KeyframeTrackNSView {
        let view = KeyframeTrackNSView()
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ nsView: KeyframeTrackNSView, context: Context) {
        nsView.keyframes = keyframes
        nsView.selectedIDs = selectedIDs
        nsView.duration = duration
        nsView.currentTime = currentTime
        nsView.draggedKeyframe = draggedKeyframe
        nsView.dragOffset = dragOffset
        nsView.needsDisplay = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, KeyframeTrackDelegate {
        var parent: KeyframeTrackView

        init(_ parent: KeyframeTrackView) {
            self.parent = parent
        }

        func trackDidSelect(_ keyframe: Keyframe, extending: Bool) {
            parent.onSelect(keyframe, extending)
        }

        func trackDidSeek(to time: Double) {
            parent.onSeek(time)
        }

        func trackDidMove(_ keyframe: Keyframe, to time: Double) {
            parent.onMove(keyframe, time)
        }

        func trackDidDelete(_ keyframe: Keyframe) {
            parent.onDelete(keyframe)
        }

        func trackDidAddKeyframe(at time: Double) {
            parent.onAddKeyframe(time)
        }

        func trackDidStartDrag(_ keyframe: Keyframe) {
            parent.draggedKeyframe = keyframe
        }

        func trackDidUpdateDrag(offset: CGFloat) {
            parent.dragOffset = offset
        }

        func trackDidEndDrag() {
            parent.draggedKeyframe = nil
            parent.dragOffset = 0
        }
    }
}

// MARK: - NSView Implementation

protocol KeyframeTrackDelegate: AnyObject {
    func trackDidSelect(_ keyframe: Keyframe, extending: Bool)
    func trackDidSeek(to time: Double)
    func trackDidMove(_ keyframe: Keyframe, to time: Double)
    func trackDidDelete(_ keyframe: Keyframe)
    func trackDidAddKeyframe(at time: Double)
    func trackDidStartDrag(_ keyframe: Keyframe)
    func trackDidUpdateDrag(offset: CGFloat)
    func trackDidEndDrag()
}

class KeyframeTrackNSView: NSView {
    weak var delegate: KeyframeTrackDelegate?

    var keyframes: [Keyframe] = []
    var selectedIDs: Set<UUID> = []
    var duration: Double = 0
    var currentTime: Double = 0
    var draggedKeyframe: Keyframe? = nil
    var dragOffset: CGFloat = 0

    private var isDragging = false
    private var dragStartX: CGFloat = 0
    private var dragStartTime: Double = 0
    private var isScrubbing = false
    private var clickCount = 0
    private var lastClickTime: Date?

    private let markerSize: CGFloat = 12
    private let hitSize: CGFloat = 20

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let rect = bounds

        // Background track
        NSColor.labelColor.withAlphaComponent(0.08).setFill()
        let trackPath = NSBezierPath(roundedRect: rect.insetBy(dx: 0, dy: 2), xRadius: 4, yRadius: 4)
        trackPath.fill()

        // Time markers
        if duration > 0 {
            NSColor.labelColor.withAlphaComponent(0.1).setStroke()
            for fraction in [0.25, 0.5, 0.75] {
                let x = CGFloat(fraction) * rect.width
                let path = NSBezierPath()
                path.move(to: NSPoint(x: x, y: 6))
                path.line(to: NSPoint(x: x, y: rect.height - 6))
                path.lineWidth = 1
                path.stroke()
            }
        }

        // Keyframe markers
        for keyframe in keyframes {
            let x = xPosition(for: keyframe)
            let isSelected = selectedIDs.contains(keyframe.id)
            let isDragged = draggedKeyframe?.id == keyframe.id

            drawKeyframeMarker(at: x, selected: isSelected, dragging: isDragged)
        }

        // Playhead
        if duration > 0 {
            let playheadX = CGFloat(currentTime / duration) * rect.width
            NSColor.red.setFill()
            NSColor.red.setStroke()

            // Triangle
            let trianglePath = NSBezierPath()
            trianglePath.move(to: NSPoint(x: playheadX - 4, y: 0))
            trianglePath.line(to: NSPoint(x: playheadX + 4, y: 0))
            trianglePath.line(to: NSPoint(x: playheadX, y: 6))
            trianglePath.close()
            trianglePath.fill()

            // Line
            let linePath = NSBezierPath()
            linePath.move(to: NSPoint(x: playheadX, y: 6))
            linePath.line(to: NSPoint(x: playheadX, y: rect.height))
            linePath.lineWidth = 2
            linePath.stroke()
        }
    }


    private func drawKeyframeMarker(at x: CGFloat, selected: Bool, dragging: Bool) {
        let y = bounds.midY
        let size: CGFloat = dragging ? 14 : 12

        // Diamond path
        let path = NSBezierPath()
        path.move(to: NSPoint(x: x, y: y - size/2))
        path.line(to: NSPoint(x: x + size/2, y: y))
        path.line(to: NSPoint(x: x, y: y + size/2))
        path.line(to: NSPoint(x: x - size/2, y: y))
        path.close()

        // Fill
        if dragging {
            NSColor.orange.setFill()
        } else if selected {
            NSColor.controlAccentColor.setFill()
        } else {
            NSColor.labelColor.withAlphaComponent(0.6).setFill()
        }
        path.fill()

        // Selection ring
        if selected && !dragging {
            let ringPath = NSBezierPath()
            let ringSize: CGFloat = 16
            ringPath.move(to: NSPoint(x: x, y: y - ringSize/2))
            ringPath.line(to: NSPoint(x: x + ringSize/2, y: y))
            ringPath.line(to: NSPoint(x: x, y: y + ringSize/2))
            ringPath.line(to: NSPoint(x: x - ringSize/2, y: y))
            ringPath.close()
            NSColor.controlAccentColor.setStroke()
            ringPath.lineWidth = 1.5
            ringPath.stroke()
        }
    }

    private func xPosition(for keyframe: Keyframe) -> CGFloat {
        guard duration > 0 else { return 0 }
        var x = CGFloat(keyframe.timestamp / duration) * bounds.width
        if draggedKeyframe?.id == keyframe.id {
            x += dragOffset
        }
        return x
    }

    private func timeAtX(_ x: CGFloat) -> Double {
        guard duration > 0, bounds.width > 0 else { return 0 }
        let fraction = max(0, min(1, x / bounds.width))
        return fraction * duration
    }

    private func keyframeAt(_ point: NSPoint) -> Keyframe? {
        for keyframe in keyframes.reversed() {
            let x = xPosition(for: keyframe)
            if abs(point.x - x) <= hitSize/2 && abs(point.y - bounds.midY) <= hitSize/2 {
                return keyframe
            }
        }
        return nil
    }

    // MARK: - Mouse Events

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let shiftPressed = event.modifierFlags.contains(.shift)

        // Track double-click
        let now = Date()
        if let lastClick = lastClickTime, now.timeIntervalSince(lastClick) < 0.3 {
            clickCount += 1
        } else {
            clickCount = 1
        }
        lastClickTime = now

        if let keyframe = keyframeAt(point) {
            // Clicked on keyframe
            if clickCount >= 2 {
                // Double-click = delete
                delegate?.trackDidDelete(keyframe)
                clickCount = 0
            } else {
                // Single click = select (with shift for extend)
                delegate?.trackDidSelect(keyframe, extending: shiftPressed)

                // Start drag
                isDragging = true
                dragStartX = point.x
                dragStartTime = keyframe.timestamp
                delegate?.trackDidStartDrag(keyframe)
            }
        } else {
            // Clicked on empty area
            if clickCount >= 2 {
                // Double-click = add keyframe
                let time = timeAtX(point.x)
                delegate?.trackDidAddKeyframe(at: time)
                clickCount = 0
            } else {
                // Single click = scrub
                isScrubbing = true
                let time = timeAtX(point.x)
                delegate?.trackDidSeek(to: time)
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if isDragging, draggedKeyframe != nil {
            let offset = point.x - dragStartX
            delegate?.trackDidUpdateDrag(offset: offset)
            needsDisplay = true
        } else if isScrubbing {
            let time = timeAtX(point.x)
            delegate?.trackDidSeek(to: time)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging, let keyframe = draggedKeyframe {
            let point = convert(event.locationInWindow, from: nil)
            let newTime = timeAtX(point.x)
            delegate?.trackDidMove(keyframe, to: newTime)
            delegate?.trackDidEndDrag()
        }

        isDragging = false
        isScrubbing = false
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if let keyframe = keyframeAt(point) {
            // Select if not selected
            if !selectedIDs.contains(keyframe.id) {
                delegate?.trackDidSelect(keyframe, extending: false)
            }

            // Show context menu
            let menu = NSMenu()
            let deleteItem = NSMenuItem(title: "Delete Keyframe", action: #selector(deleteKeyframeFromMenu(_:)), keyEquivalent: "")
            deleteItem.representedObject = keyframe
            deleteItem.target = self
            menu.addItem(deleteItem)

            if selectedIDs.count > 1 {
                let deleteAllItem = NSMenuItem(title: "Delete Selected (\(selectedIDs.count))", action: #selector(deleteSelectedFromMenu), keyEquivalent: "")
                deleteAllItem.target = self
                menu.addItem(deleteAllItem)
            }

            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }

    @objc private func deleteKeyframeFromMenu(_ sender: NSMenuItem) {
        if let keyframe = sender.representedObject as? Keyframe {
            delegate?.trackDidDelete(keyframe)
        }
    }

    @objc private func deleteSelectedFromMenu() {
        // Delete all selected via notification
        for keyframe in keyframes where selectedIDs.contains(keyframe.id) {
            delegate?.trackDidDelete(keyframe)
        }
    }

    // MARK: - Keyboard

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 51 || event.keyCode == 117 { // Delete or Forward Delete
            for keyframe in keyframes where selectedIDs.contains(keyframe.id) {
                delegate?.trackDidDelete(keyframe)
            }
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - Preview

#Preview {
    KeyframeTimelineView()
        .environmentObject(VideoPlayerViewModel())
        .environmentObject(KeyframeViewModel())
        .frame(width: 600, height: 80)
        .padding()
}
