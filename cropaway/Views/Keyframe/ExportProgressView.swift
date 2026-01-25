//
//  ExportProgressView.swift
//  cropaway
//

import SwiftUI
import AppKit

struct ExportProgressView: View {
    @EnvironmentObject var exportVM: ExportViewModel
    @Environment(\.dismiss) private var dismiss

    private var isBatchExport: Bool {
        exportVM.totalExportCount > 1
    }

    private var isComplete: Bool {
        !exportVM.isExporting && !exportVM.exportedURLs.isEmpty
    }

    var body: some View {
        VStack(spacing: 24) {
            if isComplete {
                completionView
            } else {
                progressView
            }
        }
        .padding(32)
        .frame(width: 380, height: 240)
    }

    @ViewBuilder
    private var progressView: some View {
        VStack(spacing: 8) {
            if isBatchExport {
                Text("Exporting Videos")
                    .font(.system(size: 15, weight: .semibold))

                Text("\(exportVM.currentExportIndex) of \(exportVM.totalExportCount)")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                Text("Exporting Video")
                    .font(.system(size: 15, weight: .semibold))
            }
        }

        VStack(spacing: 12) {
            Text("\(Int(exportVM.progress * 100))%")
                .font(.system(size: 28, weight: .medium, design: .monospaced))
                .foregroundStyle(.primary)

            ProgressView(value: exportVM.progress)
                .progressViewStyle(.linear)
                .frame(width: 280)
        }

        Text("Rendering video...")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)

        Button("Cancel") {
            exportVM.cancelExport()
            dismiss()
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
    }

    @ViewBuilder
    private var completionView: some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 44))
            .foregroundStyle(.green)

        VStack(spacing: 6) {
            if exportVM.exportedURLs.count > 1 {
                Text("\(exportVM.exportedURLs.count) Videos Exported")
                    .font(.system(size: 15, weight: .semibold))
            } else {
                Text("Export Complete")
                    .font(.system(size: 15, weight: .semibold))
            }

            if let url = exportVM.lastExportURL {
                Text(url.lastPathComponent)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 280)
            }
        }

        HStack(spacing: 12) {
            Button("Reveal in Finder") {
                revealInFinder()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)

            Button("Done") {
                exportVM.exportedURLs = []
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
    }

    private func revealInFinder() {
        if let url = exportVM.lastExportURL {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

#Preview {
    ExportProgressView()
        .environmentObject(ExportViewModel())
}
