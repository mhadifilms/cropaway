//
//  CircleCropView.swift
//  cropaway
//

import SwiftUI

struct CircleCropView: View {
    @Binding var center: CGPoint
    @Binding var radius: Double
    let videoSize: CGSize
    var onEditEnded: (() -> Void)? = nil

    private let handleSize: CGFloat = 14

    // Track initial state when drag begins
    @State private var initialCenter: CGPoint = .zero
    @State private var initialRadius: Double = 0

    var body: some View {
        GeometryReader { geometry in
            if videoSize.isValid {
                let pixelCenter = center.denormalized(to: videoSize)
                let pixelRadius = radius * min(videoSize.width, videoSize.height)

                ZStack {
                    // Circle outline
                    Circle()
                        .stroke(Color.white, lineWidth: 2)
                        .shadow(color: .black.opacity(0.5), radius: 2)
                        .frame(width: pixelRadius * 2, height: pixelRadius * 2)
                        .position(pixelCenter)

                    // Crosshair at center
                    crosshair(at: pixelCenter)

                    // Center drag area (larger hit area)
                    Circle()
                        .fill(Color.white.opacity(0.001))
                        .frame(width: max(20, pixelRadius * 0.5), height: max(20, pixelRadius * 0.5))
                        .position(pixelCenter)
                        .gesture(centerDragGesture())

                    // Center handle
                    Circle()
                        .fill(Color.white)
                        .frame(width: handleSize, height: handleSize)
                        .shadow(color: .black.opacity(0.4), radius: 2)
                        .position(pixelCenter)
                        .allowsHitTesting(false)

                    // Radius handles (4 directions)
                    radiusHandle(angle: 0, pixelCenter: pixelCenter, pixelRadius: pixelRadius)
                    radiusHandle(angle: 90, pixelCenter: pixelCenter, pixelRadius: pixelRadius)
                    radiusHandle(angle: 180, pixelCenter: pixelCenter, pixelRadius: pixelRadius)
                    radiusHandle(angle: 270, pixelCenter: pixelCenter, pixelRadius: pixelRadius)
                }
            }
        }
    }

    @ViewBuilder
    private func crosshair(at position: CGPoint) -> some View {
        Group {
            Rectangle()
                .fill(Color.white.opacity(0.4))
                .frame(width: 1, height: 16)
            Rectangle()
                .fill(Color.white.opacity(0.4))
                .frame(width: 16, height: 1)
        }
        .position(position)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func radiusHandle(angle: Double, pixelCenter: CGPoint, pixelRadius: CGFloat) -> some View {
        let radians = angle * .pi / 180
        let handlePos = CGPoint(
            x: pixelCenter.x + cos(radians) * pixelRadius,
            y: pixelCenter.y + sin(radians) * pixelRadius
        )

        Circle()
            .fill(Color.white)
            .frame(width: handleSize, height: handleSize)
            .shadow(color: .black.opacity(0.4), radius: 2)
            .position(handlePos)
            .gesture(radiusDragGesture())
    }

    private func centerDragGesture() -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                // Store initial center on first drag event
                if initialCenter == .zero {
                    initialCenter = center
                }

                // Calculate delta from start to current location
                let deltaX = (value.location.x - value.startLocation.x) / videoSize.width
                let deltaY = (value.location.y - value.startLocation.y) / videoSize.height

                // Apply delta to INITIAL center, not current
                var newCenter = CGPoint(
                    x: initialCenter.x + deltaX,
                    y: initialCenter.y + deltaY
                )

                // Clamp to keep circle visible
                newCenter.x = max(radius, min(1 - radius, newCenter.x))
                newCenter.y = max(radius, min(1 - radius, newCenter.y))

                center = newCenter
            }
            .onEnded { _ in
                initialCenter = .zero
                // Notify that crop editing has ended (for auto-keyframe creation)
                onEditEnded?()
            }
    }

    private func radiusDragGesture() -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                let pixelCenter = center.denormalized(to: videoSize)
                let currentLocation = value.location

                // Calculate distance from center to current drag position
                let newPixelRadius = pixelCenter.distance(to: currentLocation)
                let newRadius = Double(newPixelRadius) / min(videoSize.width, videoSize.height)

                // Clamp radius
                let maxRadius = min(
                    min(center.x, 1 - center.x),
                    min(center.y, 1 - center.y)
                )
                radius = max(0.05, min(maxRadius, newRadius))
            }
            .onEnded { _ in
                // Notify that crop editing has ended (for auto-keyframe creation)
                onEditEnded?()
            }
    }
}

#Preview {
    CircleCropView(
        center: .constant(CGPoint(x: 0.5, y: 0.5)),
        radius: .constant(0.3),
        videoSize: CGSize(width: 640, height: 360)
    )
    .frame(width: 640, height: 360)
    .background(Color.gray)
}
