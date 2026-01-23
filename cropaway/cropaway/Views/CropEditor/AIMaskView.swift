//
//  AIMaskView.swift
//  cropaway
//

import SwiftUI

/// View for AI-based mask editing using SAM3
struct AIMaskView: View {
    @Binding var promptPoints: [AIPromptPoint]
    @Binding var maskData: Data?
    @Binding var boundingBox: CGRect
    let videoSize: CGSize
    let onEditEnded: () -> Void

    @State private var hoveredPointId: UUID?

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            ZStack {
                // Mask visualization (semi-transparent overlay where mask exists)
                if let data = maskData {
                    AIMaskOverlay(maskData: data, size: size)
                        .allowsHitTesting(false)
                }

                // Click gesture to add prompt points
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                let normalizedPoint = CGPoint(
                                    x: value.location.x / size.width,
                                    y: value.location.y / size.height
                                )
                                // Check for Option key for negative point
                                let isPositive = !NSEvent.modifierFlags.contains(.option)
                                let point = AIPromptPoint(position: normalizedPoint, isPositive: isPositive)
                                promptPoints.append(point)
                                onEditEnded()
                            }
                    )

                // Render prompt points
                ForEach(promptPoints) { point in
                    PromptPointMarker(
                        point: point,
                        size: size,
                        isHovered: hoveredPointId == point.id
                    )
                    .onHover { isHovered in
                        hoveredPointId = isHovered ? point.id : nil
                    }
                    .onTapGesture(count: 2) {
                        // Double-click to remove point
                        promptPoints.removeAll { $0.id == point.id }
                        onEditEnded()
                    }
                }

                // Bounding box visualization
                if boundingBox.width > 0 {
                    let pixelBox = boundingBox.denormalized(to: size)
                    Rectangle()
                        .stroke(Color.accentColor, lineWidth: 2)
                        .frame(width: pixelBox.width, height: pixelBox.height)
                        .position(x: pixelBox.midX, y: pixelBox.midY)
                        .allowsHitTesting(false)
                }

                // Hint when no points
                if promptPoints.isEmpty && maskData == nil {
                    VStack(spacing: 8) {
                        Image(systemName: "hand.tap")
                            .font(.system(size: 32))
                        Text("Click to select object")
                            .font(.system(size: 13))
                        Text("Option+click to exclude area")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    .foregroundStyle(.white.opacity(0.7))
                    .padding()
                    .background(Color.black.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .allowsHitTesting(false)
                }
            }
        }
    }
}

/// Marker for a single prompt point
struct PromptPointMarker: View {
    let point: AIPromptPoint
    let size: CGSize
    let isHovered: Bool

    var body: some View {
        let pixelPos = point.position.denormalized(to: size)

        Circle()
            .fill(point.isPositive ? Color.green : Color.red)
            .frame(width: isHovered ? 16 : 12, height: isHovered ? 16 : 12)
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: 2)
            )
            .shadow(color: .black.opacity(0.3), radius: 2)
            .position(x: pixelPos.x, y: pixelPos.y)
    }
}

/// Semi-transparent overlay showing the AI mask
struct AIMaskOverlay: View {
    let maskData: Data
    let size: CGSize

    var body: some View {
        Canvas { context, canvasSize in
            // Decode and render the mask
            let width = Int(canvasSize.width)
            let height = Int(canvasSize.height)

            guard let bitmap = AIMaskResult.decodeMask(maskData, width: width, height: height) else {
                return
            }

            // Create image from bitmap
            guard let cgContext = CGContext(
                data: UnsafeMutableRawPointer(mutating: bitmap),
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width,
                space: CGColorSpaceCreateDeviceGray(),
                bitmapInfo: CGImageAlphaInfo.none.rawValue
            ), let cgImage = cgContext.makeImage() else {
                return
            }

            // Draw with tint
            context.opacity = 0.4
            context.draw(
                Image(decorative: cgImage, scale: 1.0),
                in: CGRect(origin: .zero, size: canvasSize)
            )
        }
        .blendMode(.sourceAtop)
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var points: [AIPromptPoint] = []
        @State var maskData: Data? = nil
        @State var boundingBox: CGRect = .zero

        var body: some View {
            AIMaskView(
                promptPoints: $points,
                maskData: $maskData,
                boundingBox: $boundingBox,
                videoSize: CGSize(width: 1920, height: 1080),
                onEditEnded: {}
            )
            .frame(width: 640, height: 360)
            .background(Color.gray)
        }
    }
    return PreviewWrapper()
}
