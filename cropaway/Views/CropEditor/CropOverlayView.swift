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
                        freehandPoints: cropEditorVM.freehandPoints
                    )

                    // Mode-specific crop editor
                    switch cropEditorVM.mode {
                    case .rectangle:
                        RectangleCropView(
                            rect: $cropEditorVM.cropRect,
                            videoSize: fittedSize,
                            onEditEnded: cropEditorVM.notifyCropEditEnded
                        )
                    case .circle:
                        CircleCropView(
                            center: $cropEditorVM.circleCenter,
                            radius: $cropEditorVM.circleRadius,
                            videoSize: fittedSize,
                            onEditEnded: cropEditorVM.notifyCropEditEnded
                        )
                    case .freehand:
                        FreehandMaskView(
                            points: $cropEditorVM.freehandPoints,
                            isDrawing: $cropEditorVM.isDrawing,
                            pathData: $cropEditorVM.freehandPathData,
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
                    guard freehandPoints.count >= 3 else { return }
                    var path = Path()
                    let first = freehandPoints[0].denormalized(to: size)
                    path.move(to: first)
                    for point in freehandPoints.dropFirst() {
                        path.addLine(to: point.denormalized(to: size))
                    }
                    path.closeSubpath()
                    context.fill(path, with: .color(.white))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

#Preview {
    CropOverlayView(videoSize: CGSize(width: 1920, height: 1080))
        .environmentObject(CropEditorViewModel())
        .frame(width: 640, height: 360)
        .background(Color.gray)
}
