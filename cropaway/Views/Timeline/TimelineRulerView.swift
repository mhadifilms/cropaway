//
//  TimelineRulerView.swift
//  Cropaway
//
//  Displays timecode ruler with frame markers above the timeline.
//

import SwiftUI

struct TimelineRulerView: View {
    let duration: Double
    let zoomLevel: Double  // Pixels per second
    let inPoint: Double?
    let outPoint: Double?
    let frameRate: Double
    
    private let rulerHeight: CGFloat = 20
    private let majorTickInterval: Double = 1.0  // Seconds
    
    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                drawRuler(context: context, size: size)
            }
            .frame(height: rulerHeight)
        }
        .frame(height: rulerHeight)
    }
    
    private func drawRuler(context: GraphicsContext, size: CGSize) {
        let width = duration * zoomLevel
        
        // Draw background
        context.fill(
            Path(CGRect(x: 0, y: 0, width: width, height: size.height)),
            with: .color(.black.opacity(0.1))
        )
        
        // Draw in/out points if set
        if let inPoint = inPoint {
            let x = inPoint * zoomLevel
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(path, with: .color(.green), lineWidth: 2)
        }
        
        if let outPoint = outPoint {
            let x = outPoint * zoomLevel
            var path = Path()
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(path, with: .color(.red), lineWidth: 2)
        }
        
        // Draw time markers
        let numSeconds = Int(ceil(duration))
        
        for second in 0...numSeconds {
            let time = Double(second)
            let x = time * zoomLevel
            
            guard x <= width else { break }
            
            // Major tick (every second)
            var tickPath = Path()
            tickPath.move(to: CGPoint(x: x, y: size.height - 6))
            tickPath.addLine(to: CGPoint(x: x, y: size.height))
            context.stroke(tickPath, with: .color(.primary), lineWidth: 1)
            
            // Draw timecode label (only if there's space)
            if zoomLevel > 30 {
                let timecode = formatTimecode(time)
                let text = Text(timecode)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(.primary)
                
                context.draw(text, at: CGPoint(x: x + 2, y: 2))
            }
        }
    }
    
    private func formatTimecode(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        let frames = Int((seconds - Double(totalSeconds)) * frameRate)
        
        return String(format: "%02d:%02d:%02d", minutes, secs, frames)
    }
}

struct TimelineRulerView_Previews: PreviewProvider {
    static var previews: some View {
        TimelineRulerView(
            duration: 30.0,
            zoomLevel: 100.0,
            inPoint: 5.0,
            outPoint: 25.0,
            frameRate: 30.0
        )
        .frame(height: 30)
        .padding()
    }
}
