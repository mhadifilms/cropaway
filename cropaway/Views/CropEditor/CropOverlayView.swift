//
//  CropOverlayView.swift
//  cropaway
//

import SwiftUI

struct CropOverlayView: View {
    let videoSize: CGSize

    @EnvironmentObject var cropEditorVM: CropEditorViewModel

    var body: some View {
        GeometryReader { geometry in
            let viewSize = geometry.size

            // Guard against invalid sizes
            if videoSize.isValid && viewSize.isValid {
                let fittedSize = videoSize.fitting(in: viewSize)
                let offset = CGSize(
                    width: (viewSize.width - fittedSize.width) / 2,
                    height: (viewSize.height - fittedSize.height) / 2
                )

                ZStack {
                    // Dimmed overlay outside crop area
                    DimmedOverlayView(
                        cropArea: cropEditorVM.effectiveCropRect,
                        mode: cropEditorVM.mode,
                        circleCenter: cropEditorVM.circleCenter,
                        circleRadius: cropEditorVM.circleRadius,
                        freehandPoints: cropEditorVM.freehandPoints,
                        freehandPathData: cropEditorVM.freehandPathData,
                        aiMaskData: cropEditorVM.aiMaskData,
                        aiBoundingBox: cropEditorVM.aiBoundingBox
                    )

                    // Mode-specific crop editor
                    switch cropEditorVM.mode {
                    case .rectangle:
                        RectangleCropView(
                            rect: Binding(
                                get: { cropEditorVM.cropRect },
                                set: { cropEditorVM.cropRect = $0 }
                            ),
                            videoSize: fittedSize,
                            onEditEnded: cropEditorVM.notifyCropEditEnded
                        )
                    case .circle:
                        CircleCropView(
                            center: Binding(
                                get: { cropEditorVM.circleCenter },
                                set: { cropEditorVM.circleCenter = $0 }
                            ),
                            radius: Binding(
                                get: { cropEditorVM.circleRadius },
                                set: { cropEditorVM.circleRadius = $0 }
                            ),
                            videoSize: fittedSize,
                            onEditEnded: cropEditorVM.notifyCropEditEnded
                        )
                    case .freehand:
                        FreehandMaskView(
                            points: Binding(
                                get: { cropEditorVM.freehandPoints },
                                set: { cropEditorVM.freehandPoints = $0 }
                            ),
                            isDrawing: Binding(
                                get: { cropEditorVM.isDrawing },
                                set: { cropEditorVM.isDrawing = $0 }
                            ),
                            pathData: Binding(
                                get: { cropEditorVM.freehandPathData },
                                set: { cropEditorVM.freehandPathData = $0 }
                            ),
                            videoSize: fittedSize,
                            onEditEnded: cropEditorVM.notifyCropEditEnded
                        )
                    case .ai:
                        AIEditorView(
                            promptPoints: Binding(
                                get: { cropEditorVM.aiPromptPoints },
                                set: { cropEditorVM.aiPromptPoints = $0 }
                            ),
                            maskData: Binding(
                                get: { cropEditorVM.aiMaskData },
                                set: { cropEditorVM.aiMaskData = $0 }
                            ),
                            boundingBox: Binding(
                                get: { cropEditorVM.aiBoundingBox },
                                set: { cropEditorVM.aiBoundingBox = $0 }
                            ),
                            interactionMode: Binding(
                                get: { cropEditorVM.aiInteractionMode },
                                set: { cropEditorVM.aiInteractionMode = $0 }
                            ),
                            videoSize: fittedSize,
                            onEditEnded: cropEditorVM.notifyCropEditEnded
                        )
                    }
                }
                .frame(width: fittedSize.width, height: fittedSize.height)
                .offset(x: offset.width, y: offset.height)
            }
        }
    }
}

struct DimmedOverlayView: View {
    let cropArea: CGRect
    let mode: CropMode
    let circleCenter: CGPoint
    let circleRadius: Double
    let freehandPoints: [CGPoint]
    let freehandPathData: Data?
    let aiMaskData: Data?
    let aiBoundingBox: CGRect

    // Computed property to decode vertices once per render
    private var freehandVertices: [MaskVertex]? {
        guard let data = freehandPathData,
              let vertices = try? JSONDecoder().decode([MaskVertex].self, from: data),
              vertices.count >= 3 else {
            return nil
        }
        return vertices
    }

    // Use data hash to force Canvas re-render when bezier data changes
    private var pathDataHash: Int {
        freehandPathData?.hashValue ?? 0
    }

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            Canvas { context, canvasSize in
                // Fill entire area with dim color
                context.fill(
                    Path(CGRect(origin: .zero, size: canvasSize)),
                    with: .color(.black.opacity(0.5))
                )

                // Cut out crop area
                context.blendMode = .destinationOut

                switch mode {
                case .rectangle:
                    let pixelRect = cropArea.denormalized(to: size)
                    context.fill(Path(pixelRect), with: .color(.white))

                case .circle:
                    let pixelCenter = circleCenter.denormalized(to: size)
                    let pixelRadius = circleRadius * min(size.width, size.height)
                    let circleRect = CGRect(
                        x: pixelCenter.x - pixelRadius,
                        y: pixelCenter.y - pixelRadius,
                        width: pixelRadius * 2,
                        height: pixelRadius * 2
                    )
                    context.fill(Path(ellipseIn: circleRect), with: .color(.white))

                case .freehand:
                    // Try to use bezier path data if available (pre-decoded)
                    if let vertices = freehandVertices {
                        let path = buildBezierPath(vertices: vertices, size: size)
                        context.fill(path, with: .color(.white))
                    } else if freehandPoints.count >= 3 {
                        // Fallback to simple points
                        var path = Path()
                        let first = freehandPoints[0].denormalized(to: size)
                        path.move(to: first)
                        for point in freehandPoints.dropFirst() {
                            path.addLine(to: point.denormalized(to: size))
                        }
                        path.closeSubpath()
                        context.fill(path, with: .color(.white))
                    }

                case .ai:
                    // For AI mode, use the bounding box as the crop area
                    // The actual mask rendering is handled separately
                    if aiBoundingBox.width > 0 {
                        let pixelRect = aiBoundingBox.denormalized(to: size)
                        context.fill(Path(pixelRect), with: .color(.white))
                    }
                }
            }
            .id(pathDataHash)  // Force re-render when bezier data changes
        }
        .allowsHitTesting(false)
    }

    /// Build a SwiftUI Path with bezier curves from MaskVertex array
    private func buildBezierPath(vertices: [MaskVertex], size: CGSize) -> Path {
        Path { path in
            guard vertices.count >= 3 else { return }

            path.move(to: vertices[0].position.denormalized(to: size))

            for i in 1..<vertices.count {
                addBezierSegment(to: &path, from: vertices[i-1], to: vertices[i], size: size)
            }

            // Close the path
            addBezierSegment(to: &path, from: vertices[vertices.count - 1], to: vertices[0], size: size)
            path.closeSubpath()
        }
    }

    /// Add a bezier curve segment between two vertices
    private func addBezierSegment(to path: inout Path, from: MaskVertex, to: MaskVertex, size: CGSize) {
        let fromPx = from.position.denormalized(to: size)
        let toPx = to.position.denormalized(to: size)

        let hasFromHandle = from.controlOut != nil
        let hasToHandle = to.controlIn != nil

        if hasFromHandle && hasToHandle {
            let ctrl1 = CGPoint(
                x: fromPx.x + from.controlOut!.x * size.width,
                y: fromPx.y + from.controlOut!.y * size.height
            )
            let ctrl2 = CGPoint(
                x: toPx.x + to.controlIn!.x * size.width,
                y: toPx.y + to.controlIn!.y * size.height
            )
            path.addCurve(to: toPx, control1: ctrl1, control2: ctrl2)
        } else if hasFromHandle {
            let ctrl = CGPoint(
                x: fromPx.x + from.controlOut!.x * size.width,
                y: fromPx.y + from.controlOut!.y * size.height
            )
            path.addQuadCurve(to: toPx, control: ctrl)
        } else if hasToHandle {
            let ctrl = CGPoint(
                x: toPx.x + to.controlIn!.x * size.width,
                y: toPx.y + to.controlIn!.y * size.height
            )
            path.addQuadCurve(to: toPx, control: ctrl)
        } else {
            path.addLine(to: toPx)
        }
    }
}

#Preview {
    CropOverlayView(videoSize: CGSize(width: 1920, height: 1080))
        .environmentObject(CropEditorViewModel())
        .frame(width: 640, height: 360)
        .background(Color.gray)
}
