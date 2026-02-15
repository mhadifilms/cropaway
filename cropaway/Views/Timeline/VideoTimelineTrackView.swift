//
//  VideoTimelineTrackView.swift
//  Cropaway
//
//  Timeline view for single video showing duration, playhead, and in/out points.
//

import SwiftUI

struct VideoTimelineTrackView: View {
    @ObservedObject var video: VideoItem
    @EnvironmentObject var playerVM: VideoPlayerViewModel
    @EnvironmentObject var keyframeVM: KeyframeViewModel
    
    @State private var zoomLevel: Double = 50.0 // Pixels per second
    @State private var isDraggingPlayhead = false
    
    private let trackHeight: CGFloat = 40
    private let rulerHeight: CGFloat = 20
    
    var body: some View {
        VStack(spacing: 0) {
            // Timeline
            GeometryReader { geometry in
                ScrollView(.horizontal, showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        // Ruler
                        TimelineRulerView(
                            duration: playerVM.duration,
                            zoomLevel: zoomLevel,
                            inPoint: video.cropConfiguration.inPoint,
                            outPoint: video.cropConfiguration.outPoint,
                            frameRate: video.metadata.frameRate
                        )
                        .frame(height: rulerHeight)
                        
                        // Track
                        VStack(alignment: .leading, spacing: 0) {
                            Color.clear.frame(height: rulerHeight)
                            
                            ZStack(alignment: .leading) {
                                // Track background
                                Rectangle()
                                    .fill(Color.black.opacity(0.05))
                                    .frame(height: trackHeight)
                                
                                // Video clip representation
                                ZStack {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: playerVM.duration * zoomLevel, height: trackHeight)
                                    
                                    // Video name overlay
                                    HStack {
                                        Text(video.fileName)
                                            .font(.system(size: 10, weight: .medium))
                                            .foregroundColor(.white)
                                            .padding(.leading, 6)
                                        Spacer()
                                    }
                                    .frame(width: playerVM.duration * zoomLevel, height: trackHeight)
                                }
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(Color.blue, lineWidth: 2)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .padding(.vertical, 6)
                                
                                // Keyframe markers
                                ForEach(video.cropConfiguration.keyframes) { keyframe in
                                    KeyframeMarker()
                                        .frame(width: 6, height: 10)
                                        .offset(x: keyframe.timestamp * zoomLevel - 3, y: trackHeight / 2 - 5)
                                }
                                
                                // In/Out point markers
                                if let inPoint = video.cropConfiguration.inPoint {
                                    Rectangle()
                                        .fill(Color.green)
                                        .frame(width: 2, height: trackHeight)
                                        .offset(x: inPoint * zoomLevel - 1)
                                }
                                
                                if let outPoint = video.cropConfiguration.outPoint {
                                    Rectangle()
                                        .fill(Color.red)
                                        .frame(width: 2, height: trackHeight)
                                        .offset(x: outPoint * zoomLevel - 1)
                                }
                            }
                        }
                        
                        // Playhead
                        ZStack {
                            // Invisible hit area for easier dragging
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: 20, height: rulerHeight + trackHeight)
                                .offset(x: playerVM.currentTime * zoomLevel - 10)
                                .gesture(
                                    DragGesture()
                                        .onChanged { value in
                                            isDraggingPlayhead = true
                                            let newTime = max(0, min(value.location.x / zoomLevel, playerVM.duration))
                                            playerVM.seek(to: newTime)
                                        }
                                        .onEnded { _ in
                                            isDraggingPlayhead = false
                                        }
                                )
                            
                            // Visual playhead
                            PlayheadIndicator(
                                position: playerVM.currentTime,
                                zoomLevel: zoomLevel,
                                height: rulerHeight + trackHeight
                            )
                        }
                    }
                    .frame(width: max(playerVM.duration * zoomLevel, geometry.size.width))
                }
            }
        }
    }
    
    private func zoomIn() {
        zoomLevel = min(zoomLevel * 1.5, 200)
    }
    
    private func zoomOut() {
        zoomLevel = max(zoomLevel / 1.5, 10)
    }
    
    private func resetZoom() {
        // Fit to view
        zoomLevel = 50
    }
    
    private func setInPoint() {
        video.cropConfiguration.inPoint = playerVM.currentTime
    }
    
    private func setOutPoint() {
        video.cropConfiguration.outPoint = playerVM.currentTime
    }
    
    private func clearInOut() {
        video.cropConfiguration.inPoint = nil
        video.cropConfiguration.outPoint = nil
    }
    
    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let frames = Int((seconds - floor(seconds)) * video.metadata.frameRate)
        return String(format: "%d:%02d:%02d", mins, secs, frames)
    }
}

struct PlayheadIndicator: View {
    let position: Double
    let zoomLevel: Double
    let height: CGFloat
    
    var body: some View {
        Rectangle()
            .fill(Color.red)
            .frame(width: 2, height: height)
            .offset(x: position * zoomLevel - 1)
    }
}

struct KeyframeMarker: View {
    var body: some View {
        Diamond()
            .fill(Color.yellow)
            .overlay(Diamond().stroke(Color.orange, lineWidth: 1))
    }
}

struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}
