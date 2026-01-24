//
//  AIEditorView.swift
//  cropaway
//
//  View for AI-based mask editing.
//  Supports text prompts and bounding box selection.
//

import SwiftUI

/// View for AI-based mask editing
struct AIEditorView: View {
    @Binding var promptPoints: [AIPromptPoint]
    @Binding var maskData: Data?
    @Binding var boundingBox: CGRect
    @Binding var interactionMode: AIInteractionMode
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

                // Interaction layer based on mode
                switch interactionMode {
                case .text:
                    // Text mode: click to add point prompts (for refinement after text search)
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

                case .point:
                    // Point mode: click to select object for tracking
                    Color.clear
                        .contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onEnded { value in
                                    let normalizedPoint = CGPoint(
                                        x: value.location.x / size.width,
                                        y: value.location.y / size.height
                                    )
                                    // Clear previous points, add new one
                                    promptPoints = [AIPromptPoint(position: normalizedPoint, isPositive: true)]
                                    onEditEnded()
                                }
                        )
                }

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

                // Only show bounding box when NO mask data exists (before tracking completes)
                if maskData == nil && boundingBox.width > 0 {
                    let pixelBox = boundingBox.denormalized(to: size)
                    Rectangle()
                        .stroke(Color.accentColor, lineWidth: 2)
                        .frame(width: pixelBox.width, height: pixelBox.height)
                        .position(x: pixelBox.midX, y: pixelBox.midY)
                        .allowsHitTesting(false)
                }

                // Hint when no selection
                if promptPoints.isEmpty && maskData == nil && boundingBox.width == 0 {
                    VStack(spacing: 8) {
                        Image(systemName: interactionMode.iconName)
                            .font(.system(size: 32))
                        Text(interactionMode == .text ? "Enter text prompt above" : "Click on the object to track")
                            .font(.system(size: 13))
                        if interactionMode == .text {
                            Text("e.g., \"person\", \"car\", \"dog\"")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
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
        if let (cgImage, _, _) = AIMaskResult.decodeMaskToImage(maskData) {
            Image(decorative: cgImage, scale: 1.0)
                .resizable()
                .interpolation(.high)
                .frame(width: size.width, height: size.height)
                .opacity(0.4)
                .blendMode(.sourceAtop)
        }
    }
}

#Preview {
    struct PreviewWrapper: View {
        @State var points: [AIPromptPoint] = []
        @State var maskData: Data? = nil
        @State var boundingBox: CGRect = .zero
        @State var mode: AIInteractionMode = .text

        var body: some View {
            AIEditorView(
                promptPoints: $points,
                maskData: $maskData,
                boundingBox: $boundingBox,
                interactionMode: $mode,
                videoSize: CGSize(width: 1920, height: 1080),
                onEditEnded: {}
            )
            .frame(width: 640, height: 360)
            .background(Color.gray)
        }
    }
    return PreviewWrapper()
}
