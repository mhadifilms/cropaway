//
//  VideoDetailView.swift
//  cropaway
//

import SwiftUI
import AVKit

struct VideoDetailView: View {
    let video: VideoItem
    @Binding var viewScale: CGFloat

    @EnvironmentObject var playerVM: VideoPlayerViewModel
    @EnvironmentObject var cropEditorVM: CropEditorViewModel
    @EnvironmentObject var exportVM: ExportViewModel
    @EnvironmentObject var keyframeVM: KeyframeViewModel

    var body: some View {
        VStack(spacing: 0) {
            CropToolbarView(video: video)

            GeometryReader { geometry in
                VStack(spacing: 0) {
                    // Video with live crop preview
                    LiveCropPreviewView(
                        preserveSize: exportVM.config.preserveWidth,
                        enableAlpha: exportVM.config.enableAlphaChannel,
                        viewScale: $viewScale
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                    .clipped()

                    // Player controls
                    VideoPlayerControlsView()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(Color(NSColor.windowBackgroundColor))

                    // Keyframe timeline
                    if keyframeVM.keyframesEnabled {
                        Divider()
                        KeyframeTimelineView()
                            .frame(height: 56)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color(NSColor.windowBackgroundColor))
                    }
                }
            }
        }
    }
}

struct LiveCropPreviewView: View {
    let preserveSize: Bool
    let enableAlpha: Bool
    @Binding var viewScale: CGFloat

    @EnvironmentObject var playerVM: VideoPlayerViewModel
    @EnvironmentObject var cropEditorVM: CropEditorViewModel

    // For pinch-to-zoom gesture
    @GestureState private var magnifyBy: CGFloat = 1.0

    var body: some View {
        GeometryReader { geometry in
            let containerSize = geometry.size

            if playerVM.videoSize.isValid {
                let videoSize = playerVM.videoSize
                let cropRect = cropEditorVM.effectiveCropRect

                // Calculate display sizes
                let displayConfig = calculateDisplayConfig(
                    videoSize: videoSize,
                    cropRect: cropRect,
                    containerSize: containerSize,
                    preserveSize: preserveSize
                )

                ZStack {
                    // Background for alpha preview
                    if enableAlpha {
                        CheckerboardView()
                            .frame(width: displayConfig.frameSize.width, height: displayConfig.frameSize.height)
                    } else {
                        Color.black
                            .frame(width: displayConfig.frameSize.width, height: displayConfig.frameSize.height)
                    }

                    // Video layer with mask
                    VideoPlayerView()
                        .frame(width: displayConfig.videoDisplaySize.width, height: displayConfig.videoDisplaySize.height)
                        .mask(
                            CropMaskShape(
                                mode: cropEditorVM.mode,
                                cropRect: cropRect,
                                circleCenter: cropEditorVM.circleCenter,
                                circleRadius: cropEditorVM.circleRadius,
                                freehandPoints: cropEditorVM.freehandPoints
                            )
                        )
                        .offset(x: displayConfig.videoOffset.width, y: displayConfig.videoOffset.height)

                    // Crop handles overlay (on top of everything)
                    CropHandlesView(videoDisplaySize: displayConfig.videoDisplaySize)
                        .offset(x: displayConfig.videoOffset.width, y: displayConfig.videoOffset.height)
                }
                .frame(width: displayConfig.frameSize.width, height: displayConfig.frameSize.height)
                .scaleEffect(viewScale * magnifyBy)
                .position(x: containerSize.width / 2, y: containerSize.height / 2)
                .gesture(magnifyGesture)
            } else {
                // Loading state
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var magnifyGesture: some Gesture {
        MagnifyGesture()
            .updating($magnifyBy) { value, state, _ in
                state = value.magnification
            }
            .onEnded { value in
                let newScale = viewScale * value.magnification
                viewScale = max(0.5, min(3.0, newScale))
            }
    }

    struct DisplayConfig {
        var frameSize: CGSize
        var videoDisplaySize: CGSize
        var videoOffset: CGSize
    }

    func calculateDisplayConfig(
        videoSize: CGSize,
        cropRect: CGRect,
        containerSize: CGSize,
        preserveSize: Bool
    ) -> DisplayConfig {
        if preserveSize {
            // Show full video size, fit to container
            let fittedSize = videoSize.fitting(in: containerSize)
            return DisplayConfig(
                frameSize: fittedSize,
                videoDisplaySize: fittedSize,
                videoOffset: .zero
            )
        } else {
            // Show only cropped region
            let croppedSize = CGSize(
                width: videoSize.width * cropRect.width,
                height: videoSize.height * cropRect.height
            )
            let fittedCroppedSize = croppedSize.fitting(in: containerSize)
            let scale = fittedCroppedSize.width / croppedSize.width

            let fullVideoDisplaySize = CGSize(
                width: videoSize.width * scale,
                height: videoSize.height * scale
            )

            // Offset to center the crop region
            let offsetX = -(cropRect.midX - 0.5) * fullVideoDisplaySize.width
            let offsetY = -(cropRect.midY - 0.5) * fullVideoDisplaySize.height

            return DisplayConfig(
                frameSize: fittedCroppedSize,
                videoDisplaySize: fullVideoDisplaySize,
                videoOffset: CGSize(width: offsetX, height: offsetY)
            )
        }
    }
}

struct CropMaskShape: Shape {
    let mode: CropMode
    let cropRect: CGRect
    let circleCenter: CGPoint
    let circleRadius: Double
    let freehandPoints: [CGPoint]

    func path(in rect: CGRect) -> Path {
        switch mode {
        case .rectangle:
            let pixelRect = cropRect.denormalized(to: rect.size)
            return Path(pixelRect)

        case .circle:
            let center = circleCenter.denormalized(to: rect.size)
            let radius = circleRadius * min(rect.width, rect.height)
            return Path(ellipseIn: CGRect(
                x: center.x - radius,
                y: center.y - radius,
                width: radius * 2,
                height: radius * 2
            ))

        case .freehand:
            guard freehandPoints.count >= 3 else {
                return Path(rect)
            }
            var path = Path()
            let first = freehandPoints[0].denormalized(to: rect.size)
            path.move(to: first)
            for point in freehandPoints.dropFirst() {
                path.addLine(to: point.denormalized(to: rect.size))
            }
            path.closeSubpath()
            return path

        case .ai:
            // AI mode uses full frame for path shape; actual mask is applied separately
            return Path(rect)
        }
    }
}

struct CropHandlesView: View {
    let videoDisplaySize: CGSize

    @EnvironmentObject var cropEditorVM: CropEditorViewModel

    var body: some View {
        if videoDisplaySize.isValid {
            ZStack {
                switch cropEditorVM.mode {
                case .rectangle:
                    RectangleCropView(
                        rect: $cropEditorVM.cropRect,
                        videoSize: videoDisplaySize
                    )
                case .circle:
                    CircleCropView(
                        center: $cropEditorVM.circleCenter,
                        radius: $cropEditorVM.circleRadius,
                        videoSize: videoDisplaySize
                    )
                case .freehand:
                    FreehandMaskView(
                        points: $cropEditorVM.freehandPoints,
                        isDrawing: $cropEditorVM.isDrawing,
                        pathData: $cropEditorVM.freehandPathData,
                        videoSize: videoDisplaySize,
                        onEditEnded: cropEditorVM.notifyCropEditEnded
                    )
                case .ai:
                    AIMaskView(
                        promptPoints: $cropEditorVM.aiPromptPoints,
                        maskData: $cropEditorVM.aiMaskData,
                        boundingBox: $cropEditorVM.aiBoundingBox,
                        videoSize: videoDisplaySize,
                        onEditEnded: cropEditorVM.notifyCropEditEnded
                    )
                }
            }
            .frame(width: videoDisplaySize.width, height: videoDisplaySize.height)
        }
    }
}

struct CheckerboardView: View {
    let squareSize: CGFloat = 10

    var body: some View {
        Canvas { context, size in
            let rows = Int(ceil(size.height / squareSize))
            let cols = Int(ceil(size.width / squareSize))

            for row in 0..<rows {
                for col in 0..<cols {
                    let isLight = (row + col) % 2 == 0
                    let rect = CGRect(
                        x: CGFloat(col) * squareSize,
                        y: CGFloat(row) * squareSize,
                        width: squareSize,
                        height: squareSize
                    )
                    context.fill(
                        Path(rect),
                        with: .color(isLight ? Color(white: 0.3) : Color(white: 0.2))
                    )
                }
            }
        }
    }
}

#Preview {
    let video = VideoItem(sourceURL: URL(fileURLWithPath: "/test.mov"))
    return VideoDetailView(video: video, viewScale: .constant(1.0))
        .environmentObject(VideoPlayerViewModel())
        .environmentObject(CropEditorViewModel())
        .environmentObject(ExportViewModel())
        .environmentObject(KeyframeViewModel())
        .frame(width: 800, height: 600)
}
