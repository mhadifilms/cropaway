//
//  SequenceDetailView.swift
//  Cropaway
//
//  Main detail view for editing a sequence: player + timeline + media bin.
//

import SwiftUI
import AVKit

struct SequenceDetailView: View {
    @EnvironmentObject var projectVM: ProjectViewModel
    @EnvironmentObject var playerVM: SequencePlayerViewModel
    @EnvironmentObject var timelineVM: TimelineViewModel
    @EnvironmentObject var cropEditorVM: CropEditorViewModel
    @EnvironmentObject var keyframeVM: KeyframeViewModel
    
    @State private var mediaBinExpanded = true
    
    var body: some View {
        VStack(spacing: 0) {
            if projectVM.project.selectedSequence != nil {
                // Media bin (collapsible)
                if mediaBinExpanded {
                    MediaBinPanel(isExpanded: $mediaBinExpanded)
                        .environmentObject(projectVM)
                        .frame(height: 200)
                    
                    Divider()
                } else {
                    // Collapsed header
                    MediaBinPanel(isExpanded: $mediaBinExpanded)
                        .environmentObject(projectVM)
                        .frame(height: 32)
                    
                    Divider()
                }
                
                // Player area (flexible, takes remaining space)
                playerArea
                    .frame(minHeight: 300, maxHeight: .infinity)
                
                // Player controls
                SequencePlayerControlsView()
                    .environmentObject(playerVM)
                    .frame(height: 32)
                
                Divider()
                
                // Timeline (fixed height)
                TimelineView()
                    .environmentObject(timelineVM)
                    .environmentObject(playerVM)
                    .environmentObject(projectVM)
                    .frame(height: 200)
            } else {
                emptyState
            }
        }
        .onChange(of: projectVM.project.selectedSequence) { oldValue, newValue in
            handleSequenceChange(oldValue, newValue)
        }
        .onAppear {
            if let sequence = projectVM.project.selectedSequence {
                loadSequence(sequence)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .splitClipAtPlayhead)) { _ in
            handleSplitClipAtPlayhead()
        }
        .onReceive(NotificationCenter.default.publisher(for: .deleteSelectedClips)) { _ in
            timelineVM.deleteSelectedClips()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rippleDeleteSelectedClips)) { _ in
            timelineVM.rippleDeleteSelectedClips()
            playerVM.sequenceDidChange()
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectNextClip)) { _ in
            timelineVM.selectNextClip()
        }
        .onReceive(NotificationCenter.default.publisher(for: .selectPreviousClip)) { _ in
            timelineVM.selectPreviousClip()
        }
        .onReceive(NotificationCenter.default.publisher(for: .setInPoint)) { _ in
            timelineVM.setInPoint(at: playerVM.currentTime)
        }
        .onReceive(NotificationCenter.default.publisher(for: .setOutPoint)) { _ in
            timelineVM.setOutPoint(at: playerVM.currentTime)
        }
        .onReceive(NotificationCenter.default.publisher(for: .clearInOutPoints)) { _ in
            timelineVM.clearInOutPoints()
        }
        .onReceive(NotificationCenter.default.publisher(for: .goToInPoint)) { _ in
            if let inPoint = projectVM.project.selectedSequence?.inPoint {
                playerVM.seek(to: inPoint)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .goToOutPoint)) { _ in
            if let outPoint = projectVM.project.selectedSequence?.outPoint {
                playerVM.seek(to: outPoint)
            }
        }
    }
    
    private var playerArea: some View {
        GeometryReader { geometry in
            ZStack {
                // Video player
                if let player = playerVM.player {
                    VideoPlayer(player: player)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    Color.black
                        .overlay {
                            Text("No video loaded")
                                .foregroundColor(.white)
                        }
                }
                
                // Crop overlay (if currentClip exists)
                if let clip = playerVM.currentClip {
                    CropOverlayLayer(
                        clip: clip,
                        currentCrop: playerVM.currentClipCrop
                    )
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 400)
        .background(Color.black)
    }
    
    private var emptyState: some View {
        VStack(spacing: 20) {
            Image(systemName: "film.stack")
                .font(.system(size: 64))
                .foregroundColor(.secondary)
            
            Text("No Sequence Selected")
                .font(.title)
                .foregroundColor(.primary)
            
            Text("Select a sequence from the sidebar or create a new one")
                .font(.body)
                .foregroundColor(.secondary)
            
            Button(action: createSequence) {
                Label("Create Sequence", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private func handleSequenceChange(_ oldSequence: Sequence?, _ newSequence: Sequence?) {
        guard let sequence = newSequence else {
            playerVM.unloadSequence()
            timelineVM.unbind()
            return
        }
        
        loadSequence(sequence)
    }
    
    private func loadSequence(_ sequence: Sequence) {
        // Load sequence in player
        playerVM.loadSequence(sequence)
        
        // Bind timeline
        timelineVM.bind(to: sequence)
        
        // If there's a clip at current time, select it for editing
        if let clip = sequence.getClipAt(sequenceTime: 0) {
            cropEditorVM.bind(to: clip)
            keyframeVM.bind(to: clip, cropEditor: cropEditorVM)
        }
    }
    
    private func createSequence() {
        let sequence = projectVM.createSequence(name: "New Sequence")
        projectVM.project.selectedSequence = sequence
    }
    
    private func handleSplitClipAtPlayhead() {
        guard let sequence = projectVM.project.selectedSequence else { return }
        
        // Find clip at current playhead position
        if let clip = sequence.getClipAt(sequenceTime: playerVM.currentTime) {
            // Split the clip
            if let (_, secondClip) = timelineVM.splitClip(clip, at: playerVM.currentTime) {
                // Rebuild composition
                playerVM.sequenceDidChange()
                
                // Select the second clip
                timelineVM.selectClip(secondClip, extending: false)
            }
        }
    }
}

// MARK: - Crop Overlay Layer

struct CropOverlayLayer: View {
    @ObservedObject var clip: TimelineClip
    let currentCrop: InterpolatedCropState?
    
    var body: some View {
        GeometryReader { geometry in
            if let crop = currentCrop {
                // Draw crop overlay based on mode
                switch clip.cropConfiguration.mode {
                case .rectangle:
                    RectangleCropOverlay(cropRect: crop.cropRect, videoSize: geometry.size)
                case .circle:
                    CircleCropOverlay(
                        center: crop.circleCenter,
                        radius: crop.circleRadius,
                        videoSize: geometry.size
                    )
                case .freehand:
                    FreehandCropOverlay(points: crop.freehandPoints, videoSize: geometry.size)
                case .ai:
                    if crop.aiBoundingBox.width > 0 {
                        RectangleCropOverlay(cropRect: crop.aiBoundingBox, videoSize: geometry.size)
                    }
                }
            }
        }
    }
}

struct RectangleCropOverlay: View {
    let cropRect: CGRect
    let videoSize: CGSize
    
    var body: some View {
        let rect = CGRect(
            x: cropRect.origin.x * videoSize.width,
            y: cropRect.origin.y * videoSize.height,
            width: cropRect.width * videoSize.width,
            height: cropRect.height * videoSize.height
        )
        
        Rectangle()
            .strokeBorder(Color.green, lineWidth: 2)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
    }
}

struct CircleCropOverlay: View {
    let center: CGPoint
    let radius: Double
    let videoSize: CGSize
    
    var body: some View {
        let centerX = center.x * videoSize.width
        let centerY = center.y * videoSize.height
        let radiusPixels = radius * min(videoSize.width, videoSize.height)
        
        Circle()
            .strokeBorder(Color.green, lineWidth: 2)
            .frame(width: radiusPixels * 2, height: radiusPixels * 2)
            .position(x: centerX, y: centerY)
    }
}

struct FreehandCropOverlay: View {
    let points: [CGPoint]
    let videoSize: CGSize
    
    var body: some View {
        if points.count > 2 {
            Path { path in
                let scaledPoints = points.map { point in
                    CGPoint(x: point.x * videoSize.width, y: point.y * videoSize.height)
                }
                
                path.move(to: scaledPoints[0])
                for point in scaledPoints.dropFirst() {
                    path.addLine(to: point)
                }
                path.closeSubpath()
            }
            .stroke(Color.green, lineWidth: 2)
        }
    }
}

struct SequenceDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let projectVM = ProjectViewModel()
        let playerVM = SequencePlayerViewModel()
        let timelineVM = TimelineViewModel()
        let cropEditorVM = CropEditorViewModel()
        let keyframeVM = KeyframeViewModel()
        
        return SequenceDetailView()
            .environmentObject(projectVM)
            .environmentObject(playerVM)
            .environmentObject(timelineVM)
            .environmentObject(cropEditorVM)
            .environmentObject(keyframeVM)
    }
}
