//
//  RectangleCropView.swift
//  cropaway
//

import SwiftUI

struct RectangleCropView: View {
    @Binding var rect: CGRect
    let videoSize: CGSize
    var onEditEnded: (() -> Void)? = nil

    private let handleSize: CGFloat = 20
    private let edgeHandleThickness: CGFloat = 8
    private let strokeWidth: CGFloat = 2

    // Store initial rect when drag starts
    @State private var initialRect: CGRect = .zero

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

                    // Corner handles
                    cornerHandle(.topLeft, pixelRect: pixelRect)
                    cornerHandle(.topRight, pixelRect: pixelRect)
                    cornerHandle(.bottomLeft, pixelRect: pixelRect)
                    cornerHandle(.bottomRight, pixelRect: pixelRect)

                    // Edge handles
                    edgeHandle(.top, pixelRect: pixelRect)
                    edgeHandle(.bottom, pixelRect: pixelRect)
                    edgeHandle(.left, pixelRect: pixelRect)
                    edgeHandle(.right, pixelRect: pixelRect)

                    // Center drag area
                    Rectangle()
                        .fill(Color.white.opacity(0.001))
                        .frame(
                            width: max(1, pixelRect.width - handleSize * 2),
                            height: max(1, pixelRect.height - handleSize * 2)
                        )
                        .position(x: pixelRect.midX, y: pixelRect.midY)
                        .gesture(makeDragGesture(for: .center))
                }
            }
        }
    }

    enum Handle {
        case topLeft, topRight, bottomLeft, bottomRight
        case top, bottom, left, right
        case center
    }

    @ViewBuilder
    private func cornerHandle(_ handle: Handle, pixelRect: CGRect) -> some View {
        let pos = handlePosition(handle, in: pixelRect)
        Circle()
            .fill(Color.white)
            .frame(width: handleSize, height: handleSize)
            .shadow(color: .black.opacity(0.4), radius: 2)
            .position(pos)
            .gesture(makeDragGesture(for: handle))
    }

    @ViewBuilder
    private func edgeHandle(_ handle: Handle, pixelRect: CGRect) -> some View {
        let pos = handlePosition(handle, in: pixelRect)
        let isVertical = handle == .left || handle == .right

        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white)
            .frame(
                width: isVertical ? edgeHandleThickness : min(50, pixelRect.width * 0.3),
                height: isVertical ? min(50, pixelRect.height * 0.3) : edgeHandleThickness
            )
            .shadow(color: .black.opacity(0.4), radius: 2)
            .position(pos)
            .gesture(makeDragGesture(for: handle))
    }

    private func handlePosition(_ handle: Handle, in rect: CGRect) -> CGPoint {
        switch handle {
        case .topLeft: return CGPoint(x: rect.minX, y: rect.minY)
        case .topRight: return CGPoint(x: rect.maxX, y: rect.minY)
        case .bottomLeft: return CGPoint(x: rect.minX, y: rect.maxY)
        case .bottomRight: return CGPoint(x: rect.maxX, y: rect.maxY)
        case .top: return CGPoint(x: rect.midX, y: rect.minY)
        case .bottom: return CGPoint(x: rect.midX, y: rect.maxY)
        case .left: return CGPoint(x: rect.minX, y: rect.midY)
        case .right: return CGPoint(x: rect.maxX, y: rect.midY)
        case .center: return CGPoint(x: rect.midX, y: rect.midY)
        }
    }

    private func makeDragGesture(for handle: Handle) -> some Gesture {
        DragGesture(minimumDistance: 1)
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
                // Notify that crop editing has ended (for auto-keyframe creation)
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
        rect: .constant(CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8)),
        videoSize: CGSize(width: 640, height: 360)
    )
    .frame(width: 640, height: 360)
    .background(Color.gray)
}
