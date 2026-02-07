//
//  TransitionConfigPopover.swift
//  cropaway
//

import SwiftUI

/// Popover for configuring transition type and duration
struct TransitionConfigPopover: View {
    @ObservedObject var transition: ClipTransition
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Transition")
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            // Transition type picker
            VStack(alignment: .leading, spacing: 6) {
                Text("Type")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("", selection: $transition.type) {
                    ForEach(TransitionType.availableTypes) { type in
                        HStack {
                            Image(systemName: type.iconName)
                            Text(type.displayName)
                        }
                        .tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            // Duration slider (only for optical flow)
            if transition.type == .opticalFlow {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Duration")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.1fs", transition.duration))
                            .font(.system(.subheadline, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Slider(value: $transition.duration, in: 0.1...2.0, step: 0.1)
                        .tint(.accentColor)

                    HStack {
                        Text("0.1s")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Spacer()
                        Text("2.0s")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Type description
            Group {
                switch transition.type {
                case .cut:
                    Label("Instant cut between clips", systemImage: "scissors")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .opticalFlow:
                    Label("Smooth morph using AI frame interpolation", systemImage: "wand.and.rays")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if !TransitionType.opticalFlow.isAvailable {
                        Label("Requires macOS 26 or later", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
        .padding(16)
        .frame(width: 260)
        .animation(.easeInOut(duration: 0.2), value: transition.type)
    }
}

/// View for displaying a transition indicator with popover
struct TransitionIndicatorView: View {
    @ObservedObject var transition: ClipTransition
    @State private var showingPopover = false

    var body: some View {
        Button {
            showingPopover.toggle()
        } label: {
            ZStack {
                // Diamond shape
                Image(systemName: "diamond.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(transitionColor)
                    .rotationEffect(.degrees(0))

                // Type icon overlay
                Image(systemName: transition.type.iconName)
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingPopover, arrowEdge: .bottom) {
            TransitionConfigPopover(transition: transition)
        }
        .help(transition.type.displayName)
    }

    private var transitionColor: Color {
        switch transition.type {
        case .cut:
            return .orange
        case .opticalFlow:
            return .purple
        }
    }
}

// MARK: - Preview

#Preview("Transition Popover") {
    TransitionConfigPopover(transition: ClipTransition(afterClipIndex: 0))
        .padding()
}

#Preview("Transition Indicator") {
    HStack(spacing: 20) {
        TransitionIndicatorView(transition: ClipTransition(type: .cut, afterClipIndex: 0))
        TransitionIndicatorView(transition: ClipTransition(type: .opticalFlow, duration: 0.5, afterClipIndex: 1))
    }
    .padding()
}
