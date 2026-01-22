//
//  VideoPlayerControlsView.swift
//  cropaway
//

import SwiftUI

struct VideoPlayerControlsView: View {
    @EnvironmentObject var playerVM: VideoPlayerViewModel

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            // Go to start
            Button(action: playerVM.goToStart) {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 12))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Go to start (Home)")

            // Shuttle controls (J/K/L)
            HStack(spacing: 4) {
                Button(action: playerVM.shuttleReverse) {
                    Text("J")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .frame(width: 20, height: 20)
                        .background(playerVM.currentRate < 0 ? Color.accentColor.opacity(0.2) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.borderless)
                .help("Shuttle reverse (J) - press multiple times to increase speed")

                Button(action: playerVM.shuttleStop) {
                    Text("K")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .frame(width: 20, height: 20)
                        .background(playerVM.currentRate == 0 && !playerVM.isPlaying ? Color.accentColor.opacity(0.2) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.borderless)
                .help("Stop (K)")

                Button(action: playerVM.shuttleForward) {
                    Text("L")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .frame(width: 20, height: 20)
                        .background(playerVM.currentRate > 1 ? Color.accentColor.opacity(0.2) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.borderless)
                .help("Shuttle forward (L) - press multiple times to increase speed")
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(Color(NSColor.controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Divider()
                .frame(height: 20)

            // Step backward
            Button(action: playerVM.stepBackward) {
                Image(systemName: "backward.frame.fill")
                    .font(.system(size: 12))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Previous frame (Left Arrow)")

            // Play/Pause button
            Button(action: playerVM.togglePlayPause) {
                Image(systemName: playerVM.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16))
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("Play/Pause (Space)")

            // Step forward
            Button(action: playerVM.stepForward) {
                Image(systemName: "forward.frame.fill")
                    .font(.system(size: 12))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Next frame (Right Arrow)")

            Divider()
                .frame(height: 20)

            // Go to end
            Button(action: playerVM.goToEnd) {
                Image(systemName: "forward.end.fill")
                    .font(.system(size: 12))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Go to end (End)")

            // Loop toggle
            Button(action: playerVM.toggleLoop) {
                Image(systemName: playerVM.isLooping ? "repeat.1" : "repeat")
                    .font(.system(size: 12))
                    .foregroundStyle(playerVM.isLooping ? Color.accentColor : Color.primary)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Loop playback (\u{2318}L)")

            // Timeline scrubber
            VideoTimelineView()
                .environmentObject(playerVM)
                .frame(minWidth: 120)

            // Rate display (when not normal speed)
            if !playerVM.rateDisplayString.isEmpty {
                Text(playerVM.rateDisplayString)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // Time display
            Text("\(playerVM.currentTime.timeDisplayString) / \(playerVM.duration.timeDisplayString)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(minWidth: 110, alignment: .trailing)
        }
        .frame(height: 32)
    }
}

#Preview {
    VideoPlayerControlsView()
        .environmentObject(VideoPlayerViewModel())
        .padding()
        .frame(width: 800)
}
