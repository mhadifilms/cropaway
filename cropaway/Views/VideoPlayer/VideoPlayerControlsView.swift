//
//  VideoPlayerControlsView.swift
//  cropaway
//

import SwiftUI

struct VideoPlayerControlsView: View {
    @Environment(VideoPlayerViewModel.self) private var playerVM

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
            GlassEffectContainer {
                HStack(spacing: 4) {
                    Button(action: playerVM.shuttleReverse) {
                        Text("J")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(playerVM.currentRate < 0 ? Color.accentColor : Color(NSColor.labelColor))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.borderless)
                    .interactiveGlassButton(isSelected: playerVM.currentRate < 0)
                    .help("Shuttle reverse (J) - press multiple times to increase speed")

                    Button(action: playerVM.shuttleStop) {
                        Text("K")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(playerVM.currentRate == 0 && !playerVM.isPlaying ? Color.accentColor : Color(NSColor.labelColor))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.borderless)
                    .interactiveGlassButton(isSelected: playerVM.currentRate == 0 && !playerVM.isPlaying)
                    .help("Stop (K)")

                    Button(action: playerVM.shuttleForward) {
                        Text("L")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundStyle(playerVM.currentRate > 1 ? Color.accentColor : Color(NSColor.labelColor))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.borderless)
                    .interactiveGlassButton(isSelected: playerVM.currentRate > 1)
                    .help("Shuttle forward (L) - press multiple times to increase speed")
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
            }

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
            .circularGlassButton()
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
            
            Divider()
                .frame(height: 20)
            
            // Add to timeline button
            Button {
                NotificationCenter.default.post(name: .addVideoToTimeline, object: nil)
            } label: {
                Image(systemName: "plus.rectangle.on.rectangle")
                    .font(.system(size: 12))
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .help("Add video to timeline (\u{2318}\u{21E7}T)")

            // Timeline scrubber
            VideoTimelineView()
                .environment(playerVM)
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

            // Time display (clickable to toggle between timecode and frame count)
            Button(action: playerVM.toggleTimeDisplay) {
                Text(playerVM.showFrameCount ? playerVM.frameDisplayString : playerVM.timecodeDisplayString)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 130, alignment: .trailing)
            }
            .buttonStyle(.plain)
            .help("Click to toggle between timecode and frame count")
        }
        .frame(height: 32)
    }
}

#Preview {
    VideoPlayerControlsView()
        .environment(VideoPlayerViewModel())
        .padding()
        .frame(width: 800)
}
