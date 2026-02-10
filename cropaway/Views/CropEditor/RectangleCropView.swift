//
//  RectangleCropView.swift
//  cropaway
//

import SwiftUI

struct RectangleCropView: View {
    @Binding var rect: CGRect
    let videoSize: CGSize
    var onEditEnded: (() -> Void)? = nil

    // Visual sizes
    private let cornerHandleSize: CGFloat = 16
    private let edgeHandleThickness: CGFloat = 6
    private let strokeWidth: CGFloat = 2

    // Hit area sizes (larger than visual for easier grabbing)
    private let cornerHitSize: CGFloat = 36
    private let edgeHitSize: CGFloat = 28

    // Inset from edge when handle is at boundary (prevents clipping)
    private let edgeInset: CGFloat = 8

    // Store initial rect when drag starts
    @State private var initialRect: CGRect = .zero
    @State private var hoveredHandle: Handle? = nil

    var body: some View {
        GeometryReader { geometry in
            if videoSize.isValid {
                let pixelRect = rect.denormalized(to: videoSize)

                ZStack {
                    // Border
                    Rectangle()
                        .stroke(Color.white, lineWidth: strokeWidth)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                        .frame(width: pixelRect.width, height: pixelRect.height)
                        .position(x: pixelRect.midX, y: pixelRect.midY)

                    // Rule of thirds
                    RuleOfThirdsGrid(rect: pixelRect)

                    // Corner handles (draw order: bottom first so top is on top)
                    cornerHandle(.bottomLeft, pixelRect: pixelRect)
                    cornerHandle(.bottomRight, pixelRect: pixelRect)
                    cornerHandle(.topLeft, pixelRect: pixelRect)
                    cornerHandle(.topRight, pixelRect: pixelRect)

                    // Edge handles
                    edgeHandle(.bottom, pixelRect: pixelRect)
                    edgeHandle(.top, pixelRect: pixelRect)
                    edgeHandle(.left, pixelRect: pixelRect)
                    edgeHandle(.right, pixelRect: pixelRect)

                    // Center drag area
                    Rectangle()
                        .fill(Color.white.opacity(0.001))
                        .frame(
                            width: max(1, pixelRect.width - cornerHitSize),
                            height: max(1, pixelRect.height - cornerHitSize)
                        )
                        .position(x: pixelRect.midX, y: pixelRect.midY)
                        .gesture(makeDragGesture(for: .center))
                        .onHover { hoveredHandle = $0 ? .center : nil }
                }
            }
        }
    }

    enum Handle {
        case topLeft, topRight, bottomLeft, bottomRight
        case top, bottom, left, right
        case center
    }

    // MARK: - Corner Handles

    @ViewBuilder
    private func cornerHandle(_ handle: Handle, pixelRect: CGRect) -> some View {
        let pos = handlePosition(handle, in: pixelRect, videoSize: videoSize)
        let isHovered = hoveredHandle == handle

        ZStack {
            // Large invisible hit area
            Circle()
                .fill(Color.clear)
                .frame(width: cornerHitSize, height: cornerHitSize)
                .contentShape(Circle())

            // Visible handle
            Circle()
                .fill(Color.white)
                .frame(
                    width: isHovered ? cornerHandleSize + 4 : cornerHandleSize,
                    height: isHovered ? cornerHandleSize + 4 : cornerHandleSize
                )
                .shadow(color: .black.opacity(0.5), radius: isHovered ? 3 : 2)
                .animation(.easeOut(duration: 0.1), value: isHovered)
        }
        .position(pos)
        .gesture(makeDragGesture(for: handle))
        .onHover { hoveredHandle = $0 ? handle : nil }
    }

    // MARK: - Edge Handles

    @ViewBuilder
    private func edgeHandle(_ handle: Handle, pixelRect: CGRect) -> some View {
        let pos = handlePosition(handle, in: pixelRect, videoSize: videoSize)
        let isVertical = handle == .left || handle == .right
        let isHovered = hoveredHandle == handle

        // Calculate visual handle size (proportional to rect, capped)
        let maxHandleLength: CGFloat = 60
        let visualLength = isVertical
            ? min(maxHandleLength, pixelRect.height * 0.4)
            : min(maxHandleLength, pixelRect.width * 0.4)

        ZStack {
            // Large invisible hit area extending inward
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.clear)
                .frame(
                    width: isVertical ? edgeHitSize : max(edgeHitSize, visualLength + 20),
                    height: isVertical ? max(edgeHitSize, visualLength + 20) : edgeHitSize
                )
                .contentShape(Rectangle())

            // Visible handle
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.white)
                .frame(
                    width: isVertical ? (isHovered ? edgeHandleThickness + 2 : edgeHandleThickness) : visualLength,
                    height: isVertical ? visualLength : (isHovered ? edgeHandleThickness + 2 : edgeHandleThickness)
                )
                .shadow(color: .black.opacity(0.5), radius: isHovered ? 3 : 2)
                .animation(.easeOut(duration: 0.1), value: isHovered)
        }
        .position(pos)
        .gesture(makeDragGesture(for: handle))
        .onHover { hoveredHandle = $0 ? handle : nil }
    }

    // MARK: - Handle Positioning

    private func handlePosition(_ handle: Handle, in rect: CGRect, videoSize: CGSize) -> CGPoint {
        // Calculate insets for handles at boundaries
        let atLeft = rect.minX < edgeInset
        let atRight = rect.maxX > videoSize.width - edgeInset
        let atTop = rect.minY < edgeInset
        let atBottom = rect.maxY > videoSize.height - edgeInset

        switch handle {
        case .topLeft:
            return CGPoint(
                x: atLeft ? rect.minX + edgeInset : rect.minX,
                y: atTop ? rect.minY + edgeInset : rect.minY
            )
        case .topRight:
            return CGPoint(
                x: atRight ? rect.maxX - edgeInset : rect.maxX,
                y: atTop ? rect.minY + edgeInset : rect.minY
            )
        case .bottomLeft:
            return CGPoint(
                x: atLeft ? rect.minX + edgeInset : rect.minX,
                y: atBottom ? rect.maxY - edgeInset : rect.maxY
            )
        case .bottomRight:
            return CGPoint(
                x: atRight ? rect.maxX - edgeInset : rect.maxX,
                y: atBottom ? rect.maxY - edgeInset : rect.maxY
            )
        case .top:
            return CGPoint(
                x: rect.midX,
                y: atTop ? rect.minY + edgeInset : rect.minY
            )
        case .bottom:
            return CGPoint(
                x: rect.midX,
                y: atBottom ? rect.maxY - edgeInset : rect.maxY
            )
        case .left:
            return CGPoint(
                x: atLeft ? rect.minX + edgeInset : rect.minX,
                y: rect.midY
            )
        case .right:
            return CGPoint(
                x: atRight ? rect.maxX - edgeInset : rect.maxX,
                y: rect.midY
            )
        case .center:
            return CGPoint(x: rect.midX, y: rect.midY)
        }
    }

    // MARK: - Drag Gesture

    private func makeDragGesture(for handle: Handle) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if initialRect == .zero {
                    initialRect = rect
                }

                // Calculate delta from drag start to current position
                let deltaX = (value.location.x - value.startLocation.x) / videoSize.width
                let deltaY = (value.location.y - value.startLocation.y) / videoSize.height

                applyDelta(handle: handle, deltaX: deltaX, deltaY: deltaY)
            }
            .onEnded { _ in
                initialRect = .zero
                hoveredHandle = nil
                onEditEnded?()
            }
    }

    private func applyDelta(handle: Handle, deltaX: CGFloat, deltaY: CGFloat) {
        var newRect = initialRect

        switch handle {
        case .topLeft:
            let newX = initialRect.origin.x + deltaX
            let newY = initialRect.origin.y + deltaY
            let newWidth = initialRect.width - deltaX
            let newHeight = initialRect.height - deltaY
            newRect = CGRect(x: newX, y: newY, width: newWidth, height: newHeight)

        case .topRight:
            let newY = initialRect.origin.y + deltaY
            let newWidth = initialRect.width + deltaX
            let newHeight = initialRect.height - deltaY
            newRect = CGRect(x: initialRect.origin.x, y: newY, width: newWidth, height: newHeight)

        case .bottomLeft:
            let newX = initialRect.origin.x + deltaX
            let newWidth = initialRect.width - deltaX
            let newHeight = initialRect.height + deltaY
            newRect = CGRect(x: newX, y: initialRect.origin.y, width: newWidth, height: newHeight)

        case .bottomRight:
            let newWidth = initialRect.width + deltaX
            let newHeight = initialRect.height + deltaY
            newRect = CGRect(x: initialRect.origin.x, y: initialRect.origin.y, width: newWidth, height: newHeight)

        case .top:
            let newY = initialRect.origin.y + deltaY
            let newHeight = initialRect.height - deltaY
            newRect = CGRect(x: initialRect.origin.x, y: newY, width: initialRect.width, height: newHeight)

        case .bottom:
            let newHeight = initialRect.height + deltaY
            newRect = CGRect(x: initialRect.origin.x, y: initialRect.origin.y, width: initialRect.width, height: newHeight)

        case .left:
            let newX = initialRect.origin.x + deltaX
            let newWidth = initialRect.width - deltaX
            newRect = CGRect(x: newX, y: initialRect.origin.y, width: newWidth, height: initialRect.height)

        case .right:
            let newWidth = initialRect.width + deltaX
            newRect = CGRect(x: initialRect.origin.x, y: initialRect.origin.y, width: newWidth, height: initialRect.height)

        case .center:
            let newX = initialRect.origin.x + deltaX
            let newY = initialRect.origin.y + deltaY
            newRect = CGRect(x: newX, y: newY, width: initialRect.width, height: initialRect.height)
        }

        // Clamp and validate
        newRect = newRect.clamped()
        if newRect.width >= 0.05 && newRect.height >= 0.05 {
            rect = newRect
        }
    }
}

// MARK: - Rule of Thirds Grid

struct RuleOfThirdsGrid: View {
    let rect: CGRect

    var body: some View {
        Canvas { context, size in
            context.stroke(
                gridPath(in: rect),
                with: .color(.white.opacity(0.3)),
                lineWidth: 1
            )
        }
        .allowsHitTesting(false)
    }

    private func gridPath(in rect: CGRect) -> Path {
        var path = Path()

        // Vertical lines
        for i in 1...2 {
            let x = rect.minX + rect.width * CGFloat(i) / 3
            path.move(to: CGPoint(x: x, y: rect.minY))
            path.addLine(to: CGPoint(x: x, y: rect.maxY))
        }

        // Horizontal lines
        for i in 1...2 {
            let y = rect.minY + rect.height * CGFloat(i) / 3
            path.move(to: CGPoint(x: rect.minX, y: y))
            path.addLine(to: CGPoint(x: rect.maxX, y: y))
        }

        return path
    }
}

#Preview {
    RectangleCropView(
        rect: .constant(CGRect(x: 0, y: 0, width: 1, height: 1)),
        videoSize: CGSize(width: 640, height: 360)
    )
    .frame(width: 640, height: 360)
    .background(Color.gray)
}
