//
//  KeyframeTimelineView.swift
//  cropaway
//

import SwiftUI

struct KeyframeTimelineView: View {
    @EnvironmentObject var playerVM: VideoPlayerViewModel
    @EnvironmentObject var keyframeVM: KeyframeViewModel

    var body: some View {
        VStack(spacing: 6) {
            // Controls
            HStack(alignment: .center, spacing: 8) {
                Text("Keyframes")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                Spacer()

                Button(action: addKeyframeAtCurrentTime) {
                    Image(systemName: "plus.diamond")
                        .font(.system(size: 11))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .help("Add keyframe at current time")

                if keyframeVM.selectedKeyframe != nil {
                    Button(action: removeSelectedKeyframe) {
                        Image(systemName: "minus.diamond")
                            .font(.system(size: 11))
                            .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .help("Remove selected keyframe")
                }
            }
            .frame(height: 22)

            // Timeline
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Track background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.primary.opacity(0.05))
                        .frame(height: 24)

                    // Keyframe markers
                    ForEach(keyframeVM.keyframes) { keyframe in
                        KeyframeMarkerView(
                            keyframe: keyframe,
                            isSelected: keyframeVM.selectedKeyframe?.id == keyframe.id,
                            duration: playerVM.duration,
                            totalWidth: geometry.size.width
                        )
                        .onTapGesture {
                            keyframeVM.selectKeyframe(keyframe)
                            playerVM.seek(to: keyframe.timestamp)
                        }
                    }

                    // Playhead indicator
                    if playerVM.duration > 0 {
                        let progress = playerVM.currentTime / playerVM.duration
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: 2, height: 28)
                            .offset(x: CGFloat(progress) * geometry.size.width - 1)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 28)
        }
    }

    private func addKeyframeAtCurrentTime() {
        keyframeVM.addKeyframe(at: playerVM.currentTime)
    }

    private func removeSelectedKeyframe() {
        if let keyframe = keyframeVM.selectedKeyframe {
            keyframeVM.removeKeyframe(keyframe)
        }
    }
}

struct KeyframeMarkerView: View {
    let keyframe: Keyframe
    let isSelected: Bool
    let duration: Double
    let totalWidth: CGFloat

    var body: some View {
        let offset = duration > 0 ? CGFloat(keyframe.timestamp / duration) * totalWidth : 0

        ZStack {
            // Diamond shape
            Image(systemName: "diamond.fill")
                .font(.system(size: 12))
                .foregroundStyle(isSelected ? Color.accentColor : Color.primary)

            // Selection ring
            if isSelected {
                Image(systemName: "diamond")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .offset(x: offset - 6, y: 0)
        .help(String(format: "%.2fs - %@", keyframe.timestamp, keyframe.interpolation.displayName))
    }
}

#Preview {
    KeyframeTimelineView()
        .environmentObject(VideoPlayerViewModel())
        .environmentObject(KeyframeViewModel())
        .frame(width: 600, height: 60)
        .padding()
}
