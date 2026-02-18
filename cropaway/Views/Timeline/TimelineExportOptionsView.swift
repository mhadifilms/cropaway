//
//  TimelineExportOptionsView.swift
//  cropaway
//
//  PHASE 6: Export mode selector for timeline export

import SwiftUI

enum TimelineExportMode: String, CaseIterable {
    case fullTimeline = "Full Timeline"
    case inOutRange = "In/Out Range"
}

struct TimelineExportOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    
    let timeline: Timeline
    let onExport: (TimelineExportMode) -> Void
    
    @State private var exportMode: TimelineExportMode = .fullTimeline
    
    private var hasInOutPoints: Bool {
        timeline.inPoint != nil && timeline.outPoint != nil
    }
    
    private var exportDuration: Double {
        if exportMode == .inOutRange, let inPoint = timeline.inPoint, let outPoint = timeline.outPoint {
            return outPoint - inPoint
        }
        return timeline.totalDuration
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 4) {
                Text("Export Timeline")
                    .font(.system(size: 15, weight: .semibold))
                
                Text(timeline.name)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            
            Divider()
            
            // Export mode selector
            VStack(alignment: .leading, spacing: 12) {
                Text("Export Range")
                    .font(.system(size: 12, weight: .medium))
                
                Picker("Export Range", selection: $exportMode) {
                    Text("Full Timeline").tag(TimelineExportMode.fullTimeline)
                    Text("In/Out Range").tag(TimelineExportMode.inOutRange)
                        .disabled(!hasInOutPoints)
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                
                // Duration info
                HStack(spacing: 4) {
                    Image(systemName: "clock")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    
                    Text(formatDuration(exportDuration))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                
                // Warning if in/out range selected but not set
                if exportMode == .inOutRange && !hasInOutPoints {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("In/Out points not set. Will export full timeline.")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Divider()
            
            // Buttons
            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                
                Button("Export...") {
                    // Automatically use full timeline if in/out mode selected but points not set
                    let mode = (exportMode == .inOutRange && !hasInOutPoints) ? .fullTimeline : exportMode
                    onExport(mode)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 340)
        .onAppear {
            // Auto-select in/out range if both points are set
            if hasInOutPoints {
                exportMode = .inOutRange
            }
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let frames = Int((seconds.truncatingRemainder(dividingBy: 1)) * 30)
        return String(format: "%d:%02d:%02d", mins, secs, frames)
    }
}

#Preview {
    TimelineExportOptionsView(
        timeline: Timeline(name: "Test Timeline"),
        onExport: { _ in }
    )
}
