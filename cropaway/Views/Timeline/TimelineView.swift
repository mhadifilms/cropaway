//
//  TimelineView.swift
//  Cropaway
//
//  Main timeline component showing ruler, tracks, clips, and playhead.
//

import SwiftUI
import UniformTypeIdentifiers

struct TimelineView: View {
    @EnvironmentObject var timelineVM: TimelineViewModel
    @EnvironmentObject var playerVM: SequencePlayerViewModel
    @EnvironmentObject var projectVM: ProjectViewModel
    
    private let timelineHeight: CGFloat = 200
    private let trackHeight: CGFloat = 60
    
    var body: some View {
        VStack(spacing: 0) {
            if let sequence = timelineVM.sequence {
                // Timeline controls
                TimelineControlsView()
                
                Divider()
                
                // Scrollable timeline
                ScrollView(.horizontal, showsIndicators: true) {
                    ZStack(alignment: .topLeading) {
                        // Ruler
                        TimelineRulerView(
                            duration: sequence.duration,
                            zoomLevel: timelineVM.zoomLevel,
                            inPoint: sequence.inPoint,
                            outPoint: sequence.outPoint,
                            frameRate: sequence.frameRate
                        )
                        
                        // Track area
                        VStack(alignment: .leading, spacing: 0) {
                            // Spacer for ruler
                            Color.clear.frame(height: 30)
                            
                            // Video track
                            VideoTrackView()
                                .environmentObject(timelineVM)
                                .environmentObject(playerVM)
                                .environmentObject(projectVM)
                        }
                        
                        // Playhead
                        PlayheadView(
                            position: playerVM.currentTime,
                            zoomLevel: timelineVM.zoomLevel
                        )
                    }
                    .frame(width: max(sequence.duration * timelineVM.zoomLevel, 1000), height: timelineHeight)
                }
                .frame(height: timelineHeight)
                .background(Color(nsColor: .textBackgroundColor))
            } else {
                // Empty state
                VStack {
                    Text("No sequence selected")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }
}

// MARK: - Timeline Controls

struct TimelineControlsView: View {
    @EnvironmentObject var timelineVM: TimelineViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            // Zoom controls
            Button(action: { timelineVM.zoomOut() }) {
                Image(systemName: "minus.magnifyingglass")
            }
            
            Slider(value: $timelineVM.zoomLevel, in: 10...500)
                .frame(width: 100)
            
            Button(action: { timelineVM.zoomIn() }) {
                Image(systemName: "plus.magnifyingglass")
            }
            
            Button(action: { timelineVM.resetZoom() }) {
                Text("100%")
                    .font(.system(size: 11))
            }
            
            Divider()
                .frame(height: 20)
            
            // Selection info
            if timelineVM.hasSelection {
                Text("\(timelineVM.selectedClips.count) selected")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                
                Button(action: { timelineVM.deleteSelectedClips() }) {
                    Image(systemName: "trash")
                }
                .help("Delete selected clips")
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

// MARK: - Video Track

struct VideoTrackView: View {
    @EnvironmentObject var timelineVM: TimelineViewModel
    @EnvironmentObject var playerVM: SequencePlayerViewModel
    @EnvironmentObject var projectVM: ProjectViewModel
    
    private let trackHeight: CGFloat = 60
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            // Track background
            Rectangle()
                .fill(Color.black.opacity(0.05))
                .frame(height: trackHeight)
            
            // Clips
            if let sequence = timelineVM.sequence {
                ForEach(sequence.clips) { clip in
                    TimelineClipView(
                        clip: clip,
                        zoomLevel: timelineVM.zoomLevel,
                        isSelected: timelineVM.isSelected(clip),
                        onTap: {
                            handleClipTap(clip)
                        },
                        onDragEnded: { delta in
                            handleClipDragEnded(clip, delta: delta)
                        }
                    )
                }
            }
        }
        .frame(height: trackHeight)
        .onDrop(of: [.utf8PlainText], isTargeted: nil) { providers in
            handleDrop(providers)
        }
    }
    
    private func handleClipTap(_ clip: TimelineClip) {
        let modifiers = NSEvent.modifierFlags
        if modifiers.contains(.shift) {
            timelineVM.selectClip(clip, extending: true)
        } else {
            timelineVM.selectClip(clip, extending: false)
            // Seek to clip start
            playerVM.seek(to: clip.startTime)
        }
    }
    
    private func handleClipDragEnded(_ clip: TimelineClip, delta: CGFloat) {
        let timeDelta = delta / timelineVM.zoomLevel
        let newTime = clip.startTime + timeDelta
        timelineVM.moveClip(clip, to: max(0, newTime))
        playerVM.sequenceDidChange()
    }
    
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard timelineVM.sequence != nil else { return false }
        
        for provider in providers {
            _ = provider.loadObject(ofClass: NSString.self) { object, error in
                guard error == nil,
                      let uuidString = object as? String,
                      let assetId = UUID(uuidString: uuidString)
                else { return }
                
                // Find the media asset
                Task { @MainActor in
                    guard let asset = projectVM.project.mediaAssets.first(where: { $0.id == assetId })
                    else { return }
                    
                    // Add clip at current playhead position or end of timeline
                    let dropTime = playerVM.currentTime
                    timelineVM.addClip(
                        mediaAsset: asset,
                        at: dropTime,
                        sourceInPoint: 0,
                        sourceOutPoint: asset.metadata.duration
                    )
                    
                    // Rebuild composition
                    playerVM.sequenceDidChange()
                }
            }
        }
        
        return true
    }
}

// MARK: - Playhead

struct PlayheadView: View {
    let position: Double
    let zoomLevel: Double
    
    var body: some View {
        VStack(spacing: 0) {
            // Playhead triangle
            Triangle()
                .fill(Color.red)
                .frame(width: 12, height: 8)
            
            // Playhead line
            Rectangle()
                .fill(Color.red)
                .frame(width: 2)
        }
        .offset(x: position * zoomLevel - 1)
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct TimelineView_Previews: PreviewProvider {
    static var previews: some View {
        let project = Project()
        let sequence = project.createSequence(name: "Test Sequence")
        
        let projectVM = ProjectViewModel()
        
        let timelineVM = TimelineViewModel()
        timelineVM.bind(to: sequence)
        
        let playerVM = SequencePlayerViewModel()
        playerVM.loadSequence(sequence)
        
        return TimelineView()
            .environmentObject(projectVM)
            .environmentObject(timelineVM)
            .environmentObject(playerVM)
            .frame(height: 200)
    }
}
