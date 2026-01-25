//
//  ExportViewModel.swift
//  cropaway
//

import Combine
import Foundation
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import UserNotifications

@MainActor
final class ExportViewModel: ObservableObject {
    @Published var config = ExportConfiguration()
    @Published var isExporting: Bool = false
    @Published var progress: Double = 0
    @Published var currentExportIndex: Int = 0
    @Published var totalExportCount: Int = 0
    @Published var error: String?
    @Published var lastExportURL: URL?
    @Published var exportedURLs: [URL] = []

    private var ffmpegService: FFmpegExportService?
    private var processingService: VideoProcessingService?

    init() {
        requestNotificationPermission()
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func export(video: VideoItem) async {
        guard !isExporting else { return }

        // Show save panel
        guard let outputURL = await showSavePanel(suggestedName: video.fileName) else {
            return
        }

        config.outputURL = outputURL
        isExporting = true
        progress = 0
        error = nil

        do {
            let videoURL: URL

            // Use VideoProcessingService for keyframed exports (frame-by-frame processing)
            // Use FFmpegExportService for static exports (faster)
            if video.cropConfiguration.hasKeyframes {
                processingService = VideoProcessingService()
                videoURL = try await processingService!.processVideo(
                    source: video,
                    cropConfig: video.cropConfiguration,
                    exportConfig: config
                ) { [weak self] progressValue in
                    Task { @MainActor in
                        self?.progress = progressValue
                    }
                }
            } else {
                ffmpegService = FFmpegExportService()
                videoURL = try await ffmpegService!.exportVideo(
                    source: video,
                    cropConfig: video.cropConfiguration,
                    exportConfig: config
                ) { [weak self] progressValue in
                    Task { @MainActor in
                        self?.progress = progressValue
                    }
                }
            }

            // Update video item
            video.lastExportURL = videoURL
            video.lastExportDate = Date()
            lastExportURL = videoURL
            exportedURLs.append(videoURL)

            // Show notification and play sound for single export
            if totalExportCount <= 1 {
                showExportCompleteNotification(fileName: videoURL.lastPathComponent)
                playCompletionSound()
            }

        } catch {
            print("Export failed with error: \(error)")
            self.error = error.localizedDescription
        }

        isExporting = false
        ffmpegService = nil
        processingService = nil
    }

    /// Batch export multiple videos to a folder
    func exportAll(videos: [VideoItem]) async {
        guard !videos.isEmpty, !isExporting else { return }

        // Show folder picker
        guard let outputFolder = await showFolderPanel() else { return }

        exportedURLs = []
        totalExportCount = videos.count
        currentExportIndex = 0

        for (index, video) in videos.enumerated() {
            currentExportIndex = index + 1
            let outputURL = outputFolder.appendingPathComponent("\(video.fileName)_cropped.mov")

            config.outputURL = outputURL
            isExporting = true
            progress = 0
            error = nil

            do {
                // Delete existing file if present
                try? FileManager.default.removeItem(at: outputURL)

                let videoURL: URL

                // Use VideoProcessingService for keyframed exports
                if video.cropConfiguration.hasKeyframes {
                    processingService = VideoProcessingService()
                    videoURL = try await processingService!.processVideo(
                        source: video,
                        cropConfig: video.cropConfiguration,
                        exportConfig: config
                    ) { [weak self] progressValue in
                        Task { @MainActor in
                            self?.progress = progressValue
                        }
                    }
                } else {
                    ffmpegService = FFmpegExportService()
                    videoURL = try await ffmpegService!.exportVideo(
                        source: video,
                        cropConfig: video.cropConfiguration,
                        exportConfig: config
                    ) { [weak self] progressValue in
                        Task { @MainActor in
                            self?.progress = progressValue
                        }
                    }
                }

                video.lastExportURL = videoURL
                video.lastExportDate = Date()
                exportedURLs.append(videoURL)

            } catch {
                print("Export failed for \(video.fileName): \(error)")
                self.error = "\(video.fileName): \(error.localizedDescription)"
            }

            ffmpegService = nil
            processingService = nil
        }

        isExporting = false
        totalExportCount = 0
        currentExportIndex = 0

        // Show completion notification for batch
        if !exportedURLs.isEmpty {
            showBatchExportCompleteNotification(count: exportedURLs.count, folder: outputFolder)
            playCompletionSound()
        }
    }

    private func showFolderPanel() async -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.title = "Export All Videos"
        panel.message = "Choose a folder to save all cropped videos"
        panel.prompt = "Export Here"

        let response = await panel.begin()
        return response == .OK ? panel.url : nil
    }

    private func showExportCompleteNotification(fileName: String) {
        let content = UNMutableNotificationContent()
        content.title = "Export Complete"
        content.body = fileName
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func showBatchExportCompleteNotification(count: Int, folder: URL) {
        let content = UNMutableNotificationContent()
        content.title = "Batch Export Complete"
        content.body = "\(count) video\(count == 1 ? "" : "s") exported to \(folder.lastPathComponent)"
        content.sound = .default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func playCompletionSound() {
        NSSound(named: .init("Glass"))?.play()
    }

    func cancelExport() {
        ffmpegService?.cancel()
        processingService?.cancel()
        isExporting = false
    }

    private func showSavePanel(suggestedName: String) async -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.quickTimeMovie]
        panel.nameFieldStringValue = "\(suggestedName)_cropped.mov"
        panel.canCreateDirectories = true
        panel.title = "Export Cropped Video"
        panel.message = "Choose a location to save the cropped video"

        let response = await panel.begin()
        return response == .OK ? panel.url : nil
    }
}
