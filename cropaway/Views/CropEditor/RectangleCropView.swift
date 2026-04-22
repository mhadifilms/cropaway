//
//  RectangleCropView.swift
//  cropaway
//

import SwiftUI

struct RectangleCropView: View {
    @Binding var rect: CGRect
    let videoSize: CGSize
    var onDragStateChanged: ((Bool) -> Void)? = nil
    var onEditEnded: (() -> Void)? = nil

    // Visual sizes
    private let cornerHandleSize: CGFloat = 16
    private let edgeHandleThickness: CGFloat = 6
    private let strokeWidth: CGFloat = 2

    // Hit area sizes
    private let cornerHitSize: CGFloat = 44
    private let edgeHitSize: CGFloat = 32

    // Inset from edge when handle is at boundary
    private let edgeInset: CGFloat = 8

    var body: some View {
        GeometryReader { _ in
            if videoSize.isValid {
                let pixelRect = rect.denormalized(to: videoSize)

                ZStack {
                    // Border
                    Rectangle()
                        .stroke(Color.white, lineWidth: strokeWidth)
                        .frame(width: pixelRect.width, height: pixelRect.height)
                        .position(x: pixelRect.midX, y: pixelRect.midY)

                    // Rule of thirds
                    RuleOfThirdsGrid(rect: pixelRect)

                    // All handles rendered directly (no ForEach for better performance)
                    HandleView(handle: .topLeft, rect: $rect, videoSize: videoSize, pixelRect: pixelRect, cornerHitSize: cornerHitSize, cornerHandleSize: cornerHandleSize, edgeInset: edgeInset, onDragStateChanged: onDragStateChanged, onEditEnded: onEditEnded)
                    HandleView(handle: .topRight, rect: $rect, videoSize: videoSize, pixelRect: pixelRect, cornerHitSize: cornerHitSize, cornerHandleSize: cornerHandleSize, edgeInset: edgeInset, onDragStateChanged: onDragStateChanged, onEditEnded: onEditEnded)
                    HandleView(handle: .bottomLeft, rect: $rect, videoSize: videoSize, pixelRect: pixelRect, cornerHitSize: cornerHitSize, cornerHandleSize: cornerHandleSize, edgeInset: edgeInset, onDragStateChanged: onDragStateChanged, onEditEnded: onEditEnded)
                    HandleView(handle: .bottomRight, rect: $rect, videoSize: videoSize, pixelRect: pixelRect, cornerHitSize: cornerHitSize, cornerHandleSize: cornerHandleSize, edgeInset: edgeInset, onDragStateChanged: onDragStateChanged, onEditEnded: onEditEnded)

                    EdgeHandleView(handle: .top, rect: $rect, videoSize: videoSize, pixelRect: pixelRect, edgeHitSize: edgeHitSize, edgeHandleThickness: edgeHandleThickness, edgeInset: edgeInset, onDragStateChanged: onDragStateChanged, onEditEnded: onEditEnded)
                    EdgeHandleView(handle: .bottom, rect: $rect, videoSize: videoSize, pixelRect: pixelRect, edgeHitSize: edgeHitSize, edgeHandleThickness: edgeHandleThickness, edgeInset: edgeInset, onDragStateChanged: onDragStateChanged, onEditEnded: onEditEnded)
                    EdgeHandleView(handle: .left, rect: $rect, videoSize: videoSize, pixelRect: pixelRect, edgeHitSize: edgeHitSize, edgeHandleThickness: edgeHandleThickness, edgeInset: edgeInset, onDragStateChanged: onDragStateChanged, onEditEnded: onEditEnded)
                    EdgeHandleView(handle: .right, rect: $rect, videoSize: videoSize, pixelRect: pixelRect, edgeHitSize: edgeHitSize, edgeHandleThickness: edgeHandleThickness, edgeInset: edgeInset, onDragStateChanged: onDragStateChanged, onEditEnded: onEditEnded)

                    // Center drag
                    CenterDragView(rect: $rect, videoSize: videoSize, pixelRect: pixelRect, cornerHitSize: cornerHitSize, onDragStateChanged: onDragStateChanged, onEditEnded: onEditEnded)
                }
            }
        }
    }
}

// MARK: - Corner Handle View (isolated state)

private struct HandleView: View {
    let handle: RectHandle
    @Binding var rect: CGRect
    let videoSize: CGSize
    let pixelRect: CGRect
    let cornerHitSize: CGFloat
    let cornerHandleSize: CGFloat
    let edgeInset: CGFloat
    var onDragStateChanged: ((Bool) -> Void)?
    var onEditEnded: (() -> Void)?

    @State private var initialRect: CGRect? = nil

    var body: some View {
        let pos = handlePosition()

        Circle()
            .fill(Color.white)
            .frame(width: cornerHandleSize, height: cornerHandleSize)
            .shadow(color: .black.opacity(0.3), radius: 1)
            .frame(width: cornerHitSize, height: cornerHitSize)
            .contentShape(Circle())
            .position(pos)
            .gesture(dragGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if initialRect == nil {
                    initialRect = rect
                    onDragStateChanged?(true)
                }
                guard let start = initialRect else { return }

                let dx = (value.translation.width) / videoSize.width
                let dy = (value.translation.height) / videoSize.height

                var newRect = start
                switch handle {
                case .topLeft:
                    newRect = CGRect(x: start.minX + dx, y: start.minY + dy, width: start.width - dx, height: start.height - dy)
                case .topRight:
                    newRect = CGRect(x: start.minX, y: start.minY + dy, width: start.width + dx, height: start.height - dy)
                case .bottomLeft:
                    newRect = CGRect(x: start.minX + dx, y: start.minY, width: start.width - dx, height: start.height + dy)
                case .bottomRight:
                    newRect = CGRect(x: start.minX, y: start.minY, width: start.width + dx, height: start.height + dy)
                default: break
                }

                let clamped = newRect.clamped()
                if clamped.width >= 0.05 && clamped.height >= 0.05 {
                    rect = clamped
                }
            }
            .onEnded { _ in
                initialRect = nil
                onDragStateChanged?(false)
                onEditEnded?()
            }
    }

    private func handlePosition() -> CGPoint {
        let atLeft = pixelRect.minX < edgeInset
        let atRight = pixelRect.maxX > videoSize.width - edgeInset
        let atTop = pixelRect.minY < edgeInset
        let atBottom = pixelRect.maxY > videoSize.height - edgeInset

        switch handle {
        case .topLeft:
            return CGPoint(x: atLeft ? pixelRect.minX + edgeInset : pixelRect.minX, y: atTop ? pixelRect.minY + edgeInset : pixelRect.minY)
        case .topRight:
            return CGPoint(x: atRight ? pixelRect.maxX - edgeInset : pixelRect.maxX, y: atTop ? pixelRect.minY + edgeInset : pixelRect.minY)
        case .bottomLeft:
            return CGPoint(x: atLeft ? pixelRect.minX + edgeInset : pixelRect.minX, y: atBottom ? pixelRect.maxY - edgeInset : pixelRect.maxY)
        case .bottomRight:
            return CGPoint(x: atRight ? pixelRect.maxX - edgeInset : pixelRect.maxX, y: atBottom ? pixelRect.maxY - edgeInset : pixelRect.maxY)
        default:
            return .zero
        }
    }
}

// MARK: - Edge Handle View (isolated state)

private struct EdgeHandleView: View {
    let handle: RectHandle
    @Binding var rect: CGRect
    let videoSize: CGSize
    let pixelRect: CGRect
    let edgeHitSize: CGFloat
    let edgeHandleThickness: CGFloat
    let edgeInset: CGFloat
    var onDragStateChanged: ((Bool) -> Void)?
    var onEditEnded: (() -> Void)?

    @State private var initialRect: CGRect? = nil

    private var isVertical: Bool { handle == .left || handle == .right }

    var body: some View {
        let pos = handlePosition()
        let maxLen: CGFloat = 60
        let visualLen = isVertical ? min(maxLen, pixelRect.height * 0.4) : min(maxLen, pixelRect.width * 0.4)

        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white)
            .frame(
                width: isVertical ? edgeHandleThickness : visualLen,
                height: isVertical ? visualLen : edgeHandleThickness
            )
            .shadow(color: .black.opacity(0.3), radius: 1)
            .frame(
                width: isVertical ? edgeHitSize : max(edgeHitSize, visualLen + 20),
                height: isVertical ? max(edgeHitSize, visualLen + 20) : edgeHitSize
            )
            .contentShape(Rectangle())
            .position(pos)
            .gesture(dragGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if initialRect == nil {
                    initialRect = rect
                    onDragStateChanged?(true)
                }
                guard let start = initialRect else { return }

                let dx = value.translation.width / videoSize.width
                let dy = value.translation.height / videoSize.height

                var newRect = start
                switch handle {
                case .top:
                    newRect = CGRect(x: start.minX, y: start.minY + dy, width: start.width, height: start.height - dy)
                case .bottom:
                    newRect = CGRect(x: start.minX, y: start.minY, width: start.width, height: start.height + dy)
                case .left:
                    newRect = CGRect(x: start.minX + dx, y: start.minY, width: start.width - dx, height: start.height)
                case .right:
                    newRect = CGRect(x: start.minX, y: start.minY, width: start.width + dx, height: start.height)
                default: break
                }

                let clamped = newRect.clamped()
                if clamped.width >= 0.05 && clamped.height >= 0.05 {
                    rect = clamped
                }
            }
            .onEnded { _ in
                initialRect = nil
                onDragStateChanged?(false)
                onEditEnded?()
            }
    }

    private func handlePosition() -> CGPoint {
        let atLeft = pixelRect.minX < edgeInset
        let atRight = pixelRect.maxX > videoSize.width - edgeInset
        let atTop = pixelRect.minY < edgeInset
        let atBottom = pixelRect.maxY > videoSize.height - edgeInset

        switch handle {
        case .top:
            return CGPoint(x: pixelRect.midX, y: atTop ? pixelRect.minY + edgeInset : pixelRect.minY)
        case .bottom:
            return CGPoint(x: pixelRect.midX, y: atBottom ? pixelRect.maxY - edgeInset : pixelRect.maxY)
        case .left:
            return CGPoint(x: atLeft ? pixelRect.minX + edgeInset : pixelRect.minX, y: pixelRect.midY)
        case .right:
            return CGPoint(x: atRight ? pixelRect.maxX - edgeInset : pixelRect.maxX, y: pixelRect.midY)
        default:
            return .zero
        }
    }
}

// MARK: - Center Drag View (isolated state)

private struct CenterDragView: View {
    @Binding var rect: CGRect
    let videoSize: CGSize
    let pixelRect: CGRect
    let cornerHitSize: CGFloat
    var onDragStateChanged: ((Bool) -> Void)?
    var onEditEnded: (() -> Void)?

    @State private var initialRect: CGRect? = nil

    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.001))
            .frame(
                width: max(1, pixelRect.width - cornerHitSize),
                height: max(1, pixelRect.height - cornerHitSize)
            )
            .contentShape(Rectangle())
            .position(x: pixelRect.midX, y: pixelRect.midY)
            .gesture(dragGesture)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if initialRect == nil {
                    initialRect = rect
                    onDragStateChanged?(true)
                }
                guard let start = initialRect else { return }

                let dx = value.translation.width / videoSize.width
                let dy = value.translation.height / videoSize.height

                let newRect = CGRect(x: start.minX + dx, y: start.minY + dy, width: start.width, height: start.height)
                rect = newRect.clamped()
            }
            .onEnded { _ in
                initialRect = nil
                onDragStateChanged?(false)
                onEditEnded?()
            }
    }
}

// MARK: - Handle Enum

enum RectHandle {
    case topLeft, topRight, bottomLeft, bottomRight
    case top, bottom, left, right
    case center
}

// MARK: - Rule of Thirds Grid

struct RuleOfThirdsGrid: View {
    let rect: CGRect

    var body: some View {
        Canvas { context, _ in
            var path = Path()
            for i in 1...2 {
                let x = rect.minX + rect.width * CGFloat(i) / 3
                path.move(to: CGPoint(x: x, y: rect.minY))
                path.addLine(to: CGPoint(x: x, y: rect.maxY))
            }
            for i in 1...2 {
                let y = rect.minY + rect.height * CGFloat(i) / 3
                path.move(to: CGPoint(x: rect.minX, y: y))
                path.addLine(to: CGPoint(x: rect.maxX, y: y))
            }
            context.stroke(path, with: .color(.white.opacity(0.3)), lineWidth: 1)
        }
        .allowsHitTesting(false)
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
