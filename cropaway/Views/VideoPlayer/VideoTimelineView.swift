//
//  VideoTimelineView.swift
//  cropaway
//

import SwiftUI

struct VideoTimelineView: View {
    @EnvironmentObject var playerVM: VideoPlayerViewModel
    @State private var isDragging = false
    @State private var dragValue: Double = 0
    @State private var seekDebounceTask: Task<Void, Never>?

    /// Debounce interval for seek operations during scrubbing (in nanoseconds)
    private let seekDebounceNs: UInt64 = 50_000_000  // 50ms

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // Track background
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.primary.opacity(0.1))
                    .frame(height: 4)

                // Progress
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor)
                    .frame(width: progressWidth(in: geometry.size.width), height: 4)

                // Playhead
                Circle()
                    .fill(Color.white)
                    .frame(width: 12, height: 12)
                    .shadow(color: .black.opacity(0.3), radius: 1, x: 0, y: 1)
                    .offset(x: playheadOffset(in: geometry.size.width))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        isDragging = true
                        let progress = value.location.x / geometry.size.width
                        let clampedProgress = max(0, min(1, progress))
                        dragValue = clampedProgress * playerVM.duration

                        // Debounce seek to reduce expensive operations during rapid scrubbing
                        seekDebounceTask?.cancel()
                        seekDebounceTask = Task {
                            try? await Task.sleep(nanoseconds: seekDebounceNs)
                            if !Task.isCancelled {
                                playerVM.seek(to: dragValue)
                            }
                        }
                    }
                    .onEnded { _ in
                        // Cancel pending debounce and seek immediately on release
                        seekDebounceTask?.cancel()
                        playerVM.seek(to: dragValue)
                        isDragging = false
                    }
            )
        }
        .frame(height: 24)
    }

    private func progressWidth(in totalWidth: CGFloat) -> CGFloat {
        guard playerVM.duration > 0 else { return 0 }
        let currentTime = isDragging ? dragValue : playerVM.currentTime
        let progress = currentTime / playerVM.duration
        return CGFloat(progress) * totalWidth
    }

    private func playheadOffset(in totalWidth: CGFloat) -> CGFloat {
        guard playerVM.duration > 0 else { return -6 }
        let currentTime = isDragging ? dragValue : playerVM.currentTime
        let progress = currentTime / playerVM.duration
        return CGFloat(progress) * totalWidth - 6
    }
}

#Preview {
    VideoTimelineView()
        .environmentObject(VideoPlayerViewModel())
        .padding()
        .frame(width: 400, height: 40)
}
