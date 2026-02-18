//
//  InspectorPanelView.swift
//  cropaway
//
//  Created by Claude Code for Inspector Panel
//

import SwiftUI

struct InspectorPanelView: View {
    @Bindable var inspectorViewModel: InspectorViewModel
    @Bindable var cropEditorViewModel: CropEditorViewModel
    @Bindable var keyframeViewModel: KeyframeViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Clip Info
                if let clip = inspectorViewModel.selectedClip {
                    clipInfoSection(clip)
                } else {
                    noSelectionView
                }
                
                // Transform Section
                TransformInspectorSection(viewModel: inspectorViewModel)
                
                // PHASE 9: Audio Section
                AudioInspectorSection(viewModel: inspectorViewModel)
                
                // Crop Section
                CropInspectorSection(cropEditorViewModel: cropEditorViewModel)
                
                // Keyframes Section
                keyframeSection
                
                Spacer()
            }
            .padding(12)
        }
        .frame(width: 280)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Clip Info Section
    
    @ViewBuilder
    private func clipInfoSection(_ clip: TimelineClip) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Clip Properties")
                .font(.headline)
            
            Divider()
            
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Duration", value: String(format: "%.2fs", clip.trimmedDuration))
                    .font(.callout)
                
                LabeledContent("Start", value: String(format: "%.2fs", clip.sourceStartTime))
                    .font(.callout)
                
                if let videoItem = clip.videoItem {
                    LabeledContent("Source", value: videoItem.sourceURL.lastPathComponent)
                        .font(.callout)
                        .lineLimit(1)
                        .help(videoItem.sourceURL.lastPathComponent)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
    }
    
    @ViewBuilder
    private var noSelectionView: some View {
        VStack(spacing: 12) {
            Image(systemName: "hand.point.up.left")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            
            Text("No Clip Selected")
                .font(.headline)
            
            Text("Select a clip in the timeline to edit its properties")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
    }
    
    // MARK: - Keyframe Section
    
    @ViewBuilder
    private var keyframeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Keyframes")
                    .font(.headline)
                
                Spacer()
                
                Toggle("Enable", isOn: $keyframeViewModel.keyframesEnabled)
                    .toggleStyle(.switch)
                    .disabled(inspectorViewModel.selectedClip == nil)
            }
            
            Divider()
            
            if keyframeViewModel.keyframesEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(keyframeViewModel.keyframes.count) keyframes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Use the keyframe timeline below the video player to add and edit keyframes")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("Enable keyframes to animate crop and transform properties over time")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
    }
}

#Preview {
    @Previewable @State var inspector = InspectorViewModel()
    @Previewable @State var cropEditor = CropEditorViewModel()
    @Previewable @State var keyframe = KeyframeViewModel()
    
    InspectorPanelView(
        inspectorViewModel: inspector,
        cropEditorViewModel: cropEditor,
        keyframeViewModel: keyframe
    )
}
