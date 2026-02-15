//
//  TimelineClipView.swift
//  Cropaway
//
//  Visual representation of a clip on the timeline.
//

import SwiftUI

struct TimelineClipView: View {
    @ObservedObject var clip: TimelineClip
    let zoomLevel: Double
    let isSelected: Bool
    let trackHeight: CGFloat = 60
    
    @State private var isDragging = false
    @State private var dragOffset: CGFloat = 0
    
    var onTap: () -> Void
    var onDragEnded: (CGFloat) -> Void
    
    private var clipWidth: CGFloat {
        clip.duration * zoomLevel
    }
    
    private var clipX: CGFloat {
        clip.startTime * zoomLevel
    }
    
    var body: some View {
        ZStack(alignment: .leading) {
            // Clip background
            RoundedRectangle(cornerRadius: 4)
                .fill(clipColor)
                .overlay {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 2)
                }
            
            // Clip name
            HStack {
                Text(clip.name)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .padding(.leading, 4)
                
                Spacer()
            }
            .frame(height: trackHeight)
            
            // Trim handles (only when selected)
            if isSelected {
                HStack(spacing: 0) {
                    TrimHandleView(edge: .leading)
                    Spacer()
                    TrimHandleView(edge: .trailing)
                }
            }
        }
        .frame(width: clipWidth, height: trackHeight)
        .offset(x: isDragging ? clipX + dragOffset : clipX)
        .gesture(dragGesture)
        .onTapGesture {
            onTap()
        }
    }
    
    private var clipColor: Color {
        if let color = clip.color {
            return Color(nsColor: color)
        }
        return Color.blue.opacity(0.7)
    }
    
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                isDragging = true
                dragOffset = value.translation.width
            }
            .onEnded { value in
                isDragging = false
                onDragEnded(value.translation.width)
                dragOffset = 0
            }
    }
}

struct TrimHandleView: View {
    let edge: Edge
    
    enum Edge {
        case leading, trailing
    }
    
    var body: some View {
        Rectangle()
            .fill(Color.white.opacity(0.8))
            .frame(width: 6)
            .overlay {
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: 2)
            }
            .frame(height: 60)
            .contentShape(Rectangle())
            .cursor(.resizeLeftRight)
    }
}

// Custom cursor modifier
extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { hovering in
            if hovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

struct TimelineClipView_Previews: PreviewProvider {
    static var previews: some View {
        let asset = MediaAsset(sourceURL: URL(fileURLWithPath: "/test.mov"))
        asset.metadata.duration = 30.0
        
        let clip = TimelineClip(
            mediaAsset: asset,
            startTime: 5.0,
            sourceInPoint: 0,
            sourceOutPoint: 10.0
        )
        clip.name = "Test Clip"
        
        return TimelineClipView(
            clip: clip,
            zoomLevel: 100.0,
            isSelected: true,
            onTap: {},
            onDragEnded: { _ in }
        )
        .frame(width: 1000, height: 60)
        .padding()
    }
}
