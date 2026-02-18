//
//  CropInspectorSection.swift
//  cropaway
//
//  Created by Claude Code for Inspector Panel
//

import SwiftUI

struct CropInspectorSection: View {
    @Bindable var cropEditorViewModel: CropEditorViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Section Header
            Text("Crop")
                .font(.headline)
            
            Divider()
            
            // Crop Mode Picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Mode")
                    .font(.subheadline)
                
                Picker("Crop Mode", selection: $cropEditorViewModel.mode) {
                    Text("Rectangle").tag(CropMode.rectangle)
                    Text("Circle").tag(CropMode.circle)
                    Text("Freehand").tag(CropMode.freehand)
                    Text("AI Mask").tag(CropMode.ai)
                }
                .pickerStyle(.segmented)
            }
            
            // Mode-specific settings
            switch cropEditorViewModel.mode {
            case .rectangle:
                rectangleSettings
            case .circle:
                circleSettings
            case .freehand:
                freehandSettings
            case .ai:
                aiSettings
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .shadow(color: Color.black.opacity(0.05), radius: 2, y: 1)
    }
    
    // MARK: - Mode-Specific Settings
    
    @ViewBuilder
    private var rectangleSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            
            Text("Rectangle Crop")
                .font(.caption)
                .foregroundColor(.secondary)
            
            // X Position
            HStack {
                Text("X:")
                    .frame(width: 20, alignment: .leading)
                Slider(value: Binding(
                    get: { cropEditorViewModel.cropRect.origin.x },
                    set: { cropEditorViewModel.cropRect.origin.x = $0 }
                ), in: 0...1)
                Text(String(format: "%.2f", cropEditorViewModel.cropRect.origin.x))
                    .frame(width: 40, alignment: .trailing)
                    .font(.caption)
            }
            
            // Y Position
            HStack {
                Text("Y:")
                    .frame(width: 20, alignment: .leading)
                Slider(value: Binding(
                    get: { cropEditorViewModel.cropRect.origin.y },
                    set: { cropEditorViewModel.cropRect.origin.y = $0 }
                ), in: 0...1)
                Text(String(format: "%.2f", cropEditorViewModel.cropRect.origin.y))
                    .frame(width: 40, alignment: .trailing)
                    .font(.caption)
            }
            
            // Width
            HStack {
                Text("W:")
                    .frame(width: 20, alignment: .leading)
                Slider(value: Binding(
                    get: { cropEditorViewModel.cropRect.width },
                    set: { cropEditorViewModel.cropRect.size.width = $0 }
                ), in: 0.1...1)
                Text(String(format: "%.2f", cropEditorViewModel.cropRect.width))
                    .frame(width: 40, alignment: .trailing)
                    .font(.caption)
            }
            
            // Height
            HStack {
                Text("H:")
                    .frame(width: 20, alignment: .leading)
                Slider(value: Binding(
                    get: { cropEditorViewModel.cropRect.height },
                    set: { cropEditorViewModel.cropRect.size.height = $0 }
                ), in: 0.1...1)
                Text(String(format: "%.2f", cropEditorViewModel.cropRect.height))
                    .frame(width: 40, alignment: .trailing)
                    .font(.caption)
            }
        }
        .font(.subheadline)
    }
    
    @ViewBuilder
    private var circleSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            
            Text("Circle Crop")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            // Center X
            HStack {
                Text("Center X:")
                    .frame(width: 70, alignment: .leading)
                Slider(value: Binding(
                    get: { cropEditorViewModel.circleCenter.x },
                    set: { cropEditorViewModel.circleCenter.x = $0 }
                ), in: 0...1)
                Text(String(format: "%.2f", cropEditorViewModel.circleCenter.x))
                    .frame(width: 40, alignment: .trailing)
                    .font(.caption)
            }
            
            // Center Y
            HStack {
                Text("Center Y:")
                    .frame(width: 70, alignment: .leading)
                Slider(value: Binding(
                    get: { cropEditorViewModel.circleCenter.y },
                    set: { cropEditorViewModel.circleCenter.y = $0 }
                ), in: 0...1)
                Text(String(format: "%.2f", cropEditorViewModel.circleCenter.y))
                    .frame(width: 40, alignment: .trailing)
                    .font(.caption)
            }
            
            // Radius
            HStack {
                Text("Radius:")
                    .frame(width: 70, alignment: .leading)
                Slider(value: $cropEditorViewModel.circleRadius, in: 0.05...0.5)
                Text(String(format: "%.2f", cropEditorViewModel.circleRadius))
                    .frame(width: 40, alignment: .trailing)
                    .font(.caption)
            }
        }
        .font(.subheadline)
    }
    
    @ViewBuilder
    private var freehandSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            
            Text("Freehand Mask")
                .font(.caption)
                .foregroundColor(.secondary)
            
            HStack {
                Text("\(cropEditorViewModel.freehandPoints.count) points")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Button("Clear Mask") {
                    cropEditorViewModel.freehandPoints.removeAll()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }
    
    @ViewBuilder
    private var aiSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            
            Text("AI Mask")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            Text("Use AI tools to automatically segment objects in your video.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            
            if cropEditorViewModel.aiMaskData != nil {
                Text("AI mask applied")
                    .font(.caption)
                    .foregroundColor(.green)
            }
        }
    }
}

#Preview {
    @Previewable @State var cropEditor = CropEditorViewModel()
    
    CropInspectorSection(cropEditorViewModel: cropEditor)
        .frame(width: 280)
        .padding()
}
