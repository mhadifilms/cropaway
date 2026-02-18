//
//  TransformInspectorSection.swift
//  cropaway
//
//  Created by Claude Code for Inspector Panel
//

import SwiftUI

struct TransformInspectorSection: View {
    @Bindable var viewModel: InspectorViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section Header
            HStack {
                Text("Transform")
                    .font(.headline)
                Spacer()
                Button {
                    viewModel.resetTransform()
                } label: {
                    Text("Reset All")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            
            Divider()
            
            // Scale
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Scale")
                        .font(.subheadline)
                    Spacer()
                    Text(String(format: "%.2f×", viewModel.scale))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Slider(value: $viewModel.scale, in: 0.1...5.0)
                    .disabled(viewModel.selectedClip == nil)
            }
            
            // Position
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Position")
                        .font(.subheadline)
                    Spacer()
                    Button {
                        viewModel.resetPosition()
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Reset Position")
                }
                
                HStack {
                    Text("X:")
                        .frame(width: 20)
                    Slider(value: $viewModel.positionX, in: 0.0...1.0)
                        .disabled(viewModel.selectedClip == nil)
                    Text(String(format: "%.2f", viewModel.positionX))
                        .frame(width: 40)
                        .font(.caption)
                }
                
                HStack {
                    Text("Y:")
                        .frame(width: 20)
                    Slider(value: $viewModel.positionY, in: 0.0...1.0)
                        .disabled(viewModel.selectedClip == nil)
                    Text(String(format: "%.2f", viewModel.positionY))
                        .frame(width: 40)
                        .font(.caption)
                }
            }
            
            // Rotation
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Rotation")
                        .font(.subheadline)
                    Spacer()
                    Text(String(format: "%.1f°", viewModel.rotation))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Slider(value: $viewModel.rotation, in: -180.0...180.0)
                    .disabled(viewModel.selectedClip == nil)
            }
            
            // Flip Controls
            HStack(spacing: 16) {
                Toggle("Flip H", isOn: $viewModel.flipHorizontal)
                    .disabled(viewModel.selectedClip == nil)
                
                Toggle("Flip V", isOn: $viewModel.flipVertical)
                    .disabled(viewModel.selectedClip == nil)
            }
            .font(.subheadline)
            
            // Opacity
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Opacity")
                        .font(.subheadline)
                    Spacer()
                    Text(String(format: "%.0f%%", viewModel.opacity * 100))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Slider(value: $viewModel.opacity, in: 0.0...1.0)
                    .disabled(viewModel.selectedClip == nil)
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
    @Previewable @State var viewModel = InspectorViewModel()
    
    TransformInspectorSection(viewModel: viewModel)
        .frame(width: 280)
        .padding()
}
