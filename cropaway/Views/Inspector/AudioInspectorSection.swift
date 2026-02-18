//
//  AudioInspectorSection.swift
//  cropaway
//
//  PHASE 9: Audio controls in inspector panel

import SwiftUI

struct AudioInspectorSection: View {
    @Bindable var viewModel: InspectorViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section header
            HStack {
                Label("Audio", systemImage: "speaker.wave.2")
                    .font(.headline)
                Spacer()
            }
            
            Divider()
            
            // Mute toggle
            HStack {
                Toggle("Mute", isOn: $viewModel.isMuted)
                    .toggleStyle(.switch)
                
                Spacer()
                
                if viewModel.isMuted {
                    Image(systemName: "speaker.slash.fill")
                        .foregroundStyle(.secondary)
                }
            }
            
            // Volume slider
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Volume")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    
                    Spacer()
                    
                    Text("\(Int(viewModel.volume * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    
                    Button(action: { viewModel.volume = 1.0 }) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Reset to 100%")
                    .disabled(abs(viewModel.volume - 1.0) < 0.01)
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "speaker.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Slider(value: Binding(
                        get: { Double(viewModel.volume) },
                        set: { viewModel.volume = Float($0) }
                    ), in: 0.0...2.0, step: 0.01)
                    
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                
                // Visual feedback for volume levels
                HStack(spacing: 2) {
                    Text("0%")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    
                    Spacer()
                    
                    Text("100%")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    
                    Spacer()
                    
                    Text("200%")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.top, -4)
            }
            
            // Audio info (if available)
            if let clip = viewModel.selectedClip,
               let video = clip.videoItem {
                Divider()
                    .padding(.vertical, 4)
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Audio Info")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    
                    HStack {
                        Image(systemName: "waveform")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("Channels: \(video.metadata.audioChannels ?? 0)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    
                    if let sampleRate = video.metadata.audioSampleRate {
                        HStack {
                            Image(systemName: "metronome")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                            Text("Sample Rate: \(Int(sampleRate)) Hz")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .padding()
        .background(Color(NSColor.controlBackgroundColor).opacity(0.3))
        .cornerRadius(8)
    }
}

#Preview {
    @Previewable @State var inspectorVM = InspectorViewModel()
    
    AudioInspectorSection(viewModel: inspectorVM)
        .frame(width: 280)
        .padding()
}
