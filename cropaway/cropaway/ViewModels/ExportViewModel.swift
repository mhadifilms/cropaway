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

            // Export companion JSON
            let jsonURL = outputURL.deletingPathExtension().appendingPathExtension("json")
            try await exportJSON(for: video, to: jsonURL)

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

                // Export companion JSON
                let jsonURL = outputURL.deletingPathExtension().appendingPathExtension("json")
                try await exportJSON(for: video, to: jsonURL)

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

    private func exportJSON(for video: VideoItem, to url: URL) async throws {
        let metadata = video.metadata
        let cropConfig = video.cropConfiguration

        let sourceInfo = CropMetadataDocument.SourceFileInfo(
            fileName: video.sourceURL.lastPathComponent,
            originalWidth: metadata.width,
            originalHeight: metadata.height,
            duration: metadata.duration,
            frameRate: metadata.frameRate,
            codec: metadata.codecType,
            isHDR: metadata.isHDR,
            colorSpace: metadata.colorSpaceDescription
        )

        let staticCrop: CropMetadataDocument.StaticCropInfo
        switch cropConfig.mode {
        case .rectangle:
            staticCrop = CropMetadataDocument.StaticCropInfo(
                rectX: cropConfig.cropRect.origin.x,
                rectY: cropConfig.cropRect.origin.y,
                rectWidth: cropConfig.cropRect.width,
                rectHeight: cropConfig.cropRect.height
            )
        case .circle:
            staticCrop = CropMetadataDocument.StaticCropInfo(
                circleCenterX: cropConfig.circleCenter.x,
                circleCenterY: cropConfig.circleCenter.y,
                circleRadius: cropConfig.circleRadius
            )
        case .freehand:
            let svgPath = pointsToSVGPath(cropConfig.freehandPoints)
            staticCrop = CropMetadataDocument.StaticCropInfo(freehandPathSVG: svgPath)
        case .ai:
            staticCrop = CropMetadataDocument.StaticCropInfo(
                aiBoundingBoxX: cropConfig.aiBoundingBox.origin.x,
                aiBoundingBoxY: cropConfig.aiBoundingBox.origin.y,
                aiBoundingBoxWidth: cropConfig.aiBoundingBox.width,
                aiBoundingBoxHeight: cropConfig.aiBoundingBox.height,
                aiTextPrompt: cropConfig.aiTextPrompt,
                aiConfidence: cropConfig.aiConfidence
            )
        }

        let keyframeInfos: [CropMetadataDocument.KeyframeInfo]? = cropConfig.hasKeyframes ?
            cropConfig.keyframes.map { kf in
                let kfCrop = CropMetadataDocument.StaticCropInfo(
                    rectX: kf.cropRect.origin.x,
                    rectY: kf.cropRect.origin.y,
                    rectWidth: kf.cropRect.width,
                    rectHeight: kf.cropRect.height,
                    edgeTop: kf.edgeInsets.top,
                    edgeLeft: kf.edgeInsets.left,
                    edgeBottom: kf.edgeInsets.bottom,
                    edgeRight: kf.edgeInsets.right,
                    circleCenterX: kf.circleCenter.x,
                    circleCenterY: kf.circleCenter.y,
                    circleRadius: kf.circleRadius
                )
                return CropMetadataDocument.KeyframeInfo(
                    timestamp: kf.timestamp,
                    interpolation: kf.interpolation.rawValue,
                    crop: kfCrop
                )
            } : nil

        let cropData = CropMetadataDocument.CropData(
            mode: cropConfig.mode.rawValue,
            isAnimated: cropConfig.hasKeyframes,
            staticCrop: cropConfig.hasKeyframes ? nil : staticCrop,
            keyframes: keyframeInfos
        )

        let exportSettings = CropMetadataDocument.ExportSettingsInfo(
            preserveWidth: config.preserveWidth,
            enableAlphaChannel: config.enableAlphaChannel,
            outputCodec: config.enableAlphaChannel ? "ap4h" : metadata.codecType,
            outputWidth: metadata.width,
            outputHeight: metadata.height
        )

        let document = CropMetadataDocument(
            sourceFile: sourceInfo,
            cropData: cropData,
            exportSettings: exportSettings
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(document)
        try data.write(to: url)
    }

    private func pointsToSVGPath(_ points: [CGPoint]) -> String {
        guard !points.isEmpty else { return "" }

        var path = "M \(points[0].x) \(points[0].y)"
        for point in points.dropFirst() {
            path += " L \(point.x) \(point.y)"
        }
        path += " Z"
        return path
    }
}
