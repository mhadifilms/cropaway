//
//  CropDataStorageService.swift
//  cropaway
//
//  Persistent storage for crop configurations in .cropaway folder next to video

import Foundation
import CoreGraphics

/// Service for saving/loading crop data to .cropaway folder alongside video files
final class CropDataStorageService {
    static let shared = CropDataStorageService()

    private let fileManager = FileManager.default
    private let storageVersion = "2.0"
    private let folderName = ".cropaway"

    /// Serial queue for thread-safe file operations
    private let fileQueue = DispatchQueue(label: "com.cropaway.storage", qos: .userInitiated)

    private init() {}

    // MARK: - Public API

    /// Save crop data for a video (creates timestamped file)
    func save(video: VideoItem) throws {
        let document = createDocument(from: video)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(document)

        // Thread-safe file write
        var writeError: Error?
        var savedURL: URL?
        fileQueue.sync {
            do {
                let fileURL = try createStorageURL(for: video.sourceURL)
                try data.write(to: fileURL)
                savedURL = fileURL
            } catch {
                writeError = error
            }
        }

        if let error = writeError {
            throw error
        }

        if let url = savedURL {
            print("Crop data saved to: \(url.path)")
        }
    }

    /// Load most recent crop data for a video (returns nil if not found)
    func load(for sourceURL: URL) -> CropStorageDocument? {
        // Thread-safe file read
        return fileQueue.sync {
            guard let storageFolder = storageFolder(for: sourceURL),
                  fileManager.fileExists(atPath: storageFolder.path) else {
                return nil
            }

            // Find all crop files for this video
            let videoName = sourceURL.deletingPathExtension().lastPathComponent
            let prefix = "\(videoName)_"

            guard let files = try? fileManager.contentsOfDirectory(at: storageFolder, includingPropertiesForKeys: [.contentModificationDateKey]) else {
                return nil
            }

            // Filter to matching files and sort by modification date (newest first)
            let matchingFiles = files
                .filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "json" }
                .sorted { url1, url2 in
                    let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    return date1 > date2
                }

            // Load the most recent file
            guard let mostRecent = matchingFiles.first,
                  let data = try? Data(contentsOf: mostRecent) else {
                return nil
            }

            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            return try? decoder.decode(CropStorageDocument.self, from: data)
        }
    }

    /// Apply loaded crop data to a VideoItem
    func apply(_ document: CropStorageDocument, to video: VideoItem) {
        let config = video.cropConfiguration

        config.mode = CropMode(rawValue: document.crop.mode) ?? .rectangle

        // Rectangle
        if let rect = document.crop.rectangle {
            config.cropRect = CGRect(
                x: rect.x,
                y: rect.y,
                width: rect.width,
                height: rect.height
            )
        }

        // Circle
        if let circle = document.crop.circle {
            config.circleCenter = CGPoint(x: circle.centerX, y: circle.centerY)
            config.circleRadius = circle.radius
        }

        // Freehand
        if let freehand = document.crop.freehand {
            config.freehandPoints = freehand.vertices.map {
                CGPoint(x: $0.x, y: $0.y)
            }
            // Restore bezier data
            let maskVertices = freehand.vertices.map { v in
                MaskVertex(
                    position: CGPoint(x: v.x, y: v.y),
                    controlIn: (v.controlInX != nil && v.controlInY != nil) ?
                        CGPoint(x: v.controlInX!, y: v.controlInY!) : nil,
                    controlOut: (v.controlOutX != nil && v.controlOutY != nil) ?
                        CGPoint(x: v.controlOutX!, y: v.controlOutY!) : nil
                )
            }
            if let bezierData = try? JSONEncoder().encode(maskVertices) {
                config.freehandPathData = bezierData
            }
        }

        // AI
        if let ai = document.crop.ai {
            if let maskBase64 = ai.maskDataBase64 {
                config.aiMaskData = Data(base64Encoded: maskBase64)
            }
            config.aiBoundingBox = CGRect(
                x: ai.boundingBoxX,
                y: ai.boundingBoxY,
                width: ai.boundingBoxWidth,
                height: ai.boundingBoxHeight
            )
            config.aiTextPrompt = ai.textPrompt
            config.aiConfidence = ai.confidence
            if let promptPoints = ai.promptPoints {
                config.aiPromptPoints = promptPoints.map {
                    AIPromptPoint(position: CGPoint(x: $0.x, y: $0.y), isPositive: $0.isPositive)
                }
            }
        }

        // Keyframes
        if let keyframes = document.crop.keyframes, !keyframes.isEmpty {
            config.keyframesEnabled = true
            config.keyframes = keyframes.map { kfData in
                let kf = Keyframe(
                    timestamp: kfData.timestamp,
                    interpolation: KeyframeInterpolation(rawValue: kfData.interpolation) ?? .linear
                )

                if let rect = kfData.rectangle {
                    kf.cropRect = CGRect(x: rect.x, y: rect.y, width: rect.width, height: rect.height)
                }
                if let circle = kfData.circle {
                    kf.circleCenter = CGPoint(x: circle.centerX, y: circle.centerY)
                    kf.circleRadius = circle.radius
                }
                if let freehand = kfData.freehand {
                    let maskVertices = freehand.vertices.map { v in
                        MaskVertex(
                            position: CGPoint(x: v.x, y: v.y),
                            controlIn: (v.controlInX != nil && v.controlInY != nil) ?
                                CGPoint(x: v.controlInX!, y: v.controlInY!) : nil,
                            controlOut: (v.controlOutX != nil && v.controlOutY != nil) ?
                                CGPoint(x: v.controlOutX!, y: v.controlOutY!) : nil
                        )
                    }
                    if let data = try? JSONEncoder().encode(maskVertices) {
                        kf.freehandPathData = data
                    }
                }
                if let ai = kfData.ai {
                    if let maskBase64 = ai.maskDataBase64 {
                        kf.aiMaskData = Data(base64Encoded: maskBase64)
                    }
                    kf.aiBoundingBox = CGRect(
                        x: ai.boundingBoxX,
                        y: ai.boundingBoxY,
                        width: ai.boundingBoxWidth,
                        height: ai.boundingBoxHeight
                    )
                    if let promptPoints = ai.promptPoints {
                        kf.aiPromptPoints = promptPoints.map {
                            AIPromptPoint(position: CGPoint(x: $0.x, y: $0.y), isPositive: $0.isPositive)
                        }
                    }
                }

                return kf
            }
        }
    }

    /// List all crop data files for a video
    func listFiles(for sourceURL: URL) -> [URL] {
        // Thread-safe file listing
        return fileQueue.sync {
            guard let storageFolder = storageFolder(for: sourceURL),
                  fileManager.fileExists(atPath: storageFolder.path) else {
                return []
            }

            let videoName = sourceURL.deletingPathExtension().lastPathComponent
            let prefix = "\(videoName)_"

            guard let files = try? fileManager.contentsOfDirectory(at: storageFolder, includingPropertiesForKeys: nil) else {
                return []
            }

            return files.filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "json" }
        }
    }

    /// Delete all crop data for a video
    func deleteAll(for sourceURL: URL) {
        // Thread-safe file deletion
        fileQueue.sync {
            let files = listFilesUnsafe(for: sourceURL)
            for file in files {
                try? fileManager.removeItem(at: file)
            }
        }
    }

    /// Internal non-thread-safe listing (call only from within fileQueue)
    private func listFilesUnsafe(for sourceURL: URL) -> [URL] {
        guard let storageFolder = storageFolder(for: sourceURL),
              fileManager.fileExists(atPath: storageFolder.path) else {
            return []
        }

        let videoName = sourceURL.deletingPathExtension().lastPathComponent
        let prefix = "\(videoName)_"

        guard let files = try? fileManager.contentsOfDirectory(at: storageFolder, includingPropertiesForKeys: nil) else {
            return []
        }

        return files.filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "json" }
    }

    /// Export crop data to a custom folder (for user export, not auto-save)
    func exportToFolder(video: VideoItem, destinationFolder: URL) throws -> URL {
        let document = createDocument(from: video)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(document)

        // Create filename: videoname_crop.json
        let videoName = video.sourceURL.deletingPathExtension().lastPathComponent
        let fileName = "\(videoName)_crop.json"
        let fileURL = destinationFolder.appendingPathComponent(fileName)

        // Overwrite if exists
        try? fileManager.removeItem(at: fileURL)
        try data.write(to: fileURL)

        print("Crop data exported to: \(fileURL.path)")
        return fileURL
    }

    /// Export multiple videos to a custom folder
    func exportMultipleToFolder(videos: [VideoItem], destinationFolder: URL) throws -> [URL] {
        var exportedURLs: [URL] = []
        for video in videos where video.hasCropChanges {
            let url = try exportToFolder(video: video, destinationFolder: destinationFolder)
            exportedURLs.append(url)
        }
        return exportedURLs
    }

    // MARK: - Bounding Box Export

    /// Export bounding box data as [[x1, y1, x2, y2], ...] for each frame
    /// x1=left, y1=top, x2=right, y2=bottom in pixel coordinates
    func exportBoundingBoxData(video: VideoItem, destinationFolder: URL) throws -> URL {
        let config = video.cropConfiguration
        let meta = video.metadata

        guard meta.width > 0 && meta.height > 0 && meta.frameRate > 0 else {
            throw StorageError.invalidMetadata
        }

        // Calculate total frames
        let totalFrames = Int(ceil(meta.duration * meta.frameRate))
        guard totalFrames > 0 else {
            throw StorageError.invalidMetadata
        }

        // Generate bounding box for each frame
        var boundingBoxes: [[Int]] = []
        boundingBoxes.reserveCapacity(totalFrames)

        let width = Double(meta.width)
        let height = Double(meta.height)

        for frameIndex in 0..<totalFrames {
            let timestamp = Double(frameIndex) / meta.frameRate

            // Get crop rect at this timestamp (interpolated if keyframes exist)
            let cropRect: CGRect
            if config.hasKeyframes {
                let state = KeyframeInterpolator.shared.interpolate(
                    keyframes: config.keyframes,
                    at: timestamp,
                    mode: config.mode
                )
                cropRect = state.cropRect
            } else {
                cropRect = config.effectiveCropRect
            }

            // Convert normalized rect to pixel bounding box [x1, y1, x2, y2]
            let x1 = Int(round(cropRect.minX * width))
            let y1 = Int(round(cropRect.minY * height))
            let x2 = Int(round(cropRect.maxX * width))
            let y2 = Int(round(cropRect.maxY * height))

            boundingBoxes.append([x1, y1, x2, y2])
        }

        // Encode as JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(boundingBoxes)

        // Create filename: videoname_bbox.json
        let videoName = video.sourceURL.deletingPathExtension().lastPathComponent
        let fileName = "\(videoName)_bbox.json"
        let fileURL = destinationFolder.appendingPathComponent(fileName)

        // Overwrite if exists
        try? fileManager.removeItem(at: fileURL)
        try data.write(to: fileURL)

        print("Bounding box data exported to: \(fileURL.path) (\(totalFrames) frames)")
        return fileURL
    }

    /// Export bounding box data for multiple videos
    func exportMultipleBoundingBoxData(videos: [VideoItem], destinationFolder: URL) throws -> [URL] {
        var exportedURLs: [URL] = []
        for video in videos where video.hasCropChanges {
            let url = try exportBoundingBoxData(video: video, destinationFolder: destinationFolder)
            exportedURLs.append(url)
        }
        return exportedURLs
    }

    // MARK: - Private Helpers

    private func storageFolder(for sourceURL: URL) -> URL? {
        let videoFolder = sourceURL.deletingLastPathComponent()
        return videoFolder.appendingPathComponent(folderName, isDirectory: true)
    }

    private func createStorageURL(for sourceURL: URL) throws -> URL {
        guard let storageFolder = storageFolder(for: sourceURL) else {
            throw StorageError.invalidPath
        }

        // Create .cropaway folder if needed
        if !fileManager.fileExists(atPath: storageFolder.path) {
            try fileManager.createDirectory(at: storageFolder, withIntermediateDirectories: true)
        }

        // Create filename: videoname_YYYY-MM-DD_HH-MM-SS.json
        let videoName = sourceURL.deletingPathExtension().lastPathComponent
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestamp = dateFormatter.string(from: Date())

        let fileName = "\(videoName)_\(timestamp).json"
        return storageFolder.appendingPathComponent(fileName)
    }

    private func createDocument(from video: VideoItem) -> CropStorageDocument {
        let config = video.cropConfiguration
        let meta = video.metadata

        // Source info
        let source = CropStorageDocument.SourceInfo(
            filePath: video.sourceURL.path,
            fileName: video.sourceURL.lastPathComponent,
            width: meta.width,
            height: meta.height,
            duration: meta.duration,
            frameRate: meta.frameRate,
            codec: meta.codecType,
            isHDR: meta.isHDR,
            colorSpace: meta.colorSpaceDescription,
            bitDepth: meta.bitDepth,
            bitRate: meta.bitRate
        )

        // Crop data
        var cropData = CropStorageDocument.CropData(mode: config.mode.rawValue)

        switch config.mode {
        case .rectangle:
            cropData.rectangle = CropStorageDocument.RectangleData(
                x: Double(config.cropRect.origin.x),
                y: Double(config.cropRect.origin.y),
                width: Double(config.cropRect.width),
                height: Double(config.cropRect.height)
            )

        case .circle:
            cropData.circle = CropStorageDocument.CircleData(
                centerX: config.circleCenter.x,
                centerY: config.circleCenter.y,
                radius: config.circleRadius
            )

        case .freehand:
            let vertices = config.freehandPoints.enumerated().map { index, point in
                var vertex = CropStorageDocument.VertexData(
                    x: Double(point.x),
                    y: Double(point.y)
                )

                // Recover bezier data from stored path
                if let pathData = config.freehandPathData,
                   let maskVertices = try? JSONDecoder().decode([MaskVertex].self, from: pathData),
                   index < maskVertices.count {
                    if let ci = maskVertices[index].controlIn {
                        vertex.controlInX = Double(ci.x)
                        vertex.controlInY = Double(ci.y)
                    }
                    if let co = maskVertices[index].controlOut {
                        vertex.controlOutX = Double(co.x)
                        vertex.controlOutY = Double(co.y)
                    }
                }

                return vertex
            }

            cropData.freehand = CropStorageDocument.FreehandData(vertices: vertices)

        case .ai:
            let promptPointsData = config.aiPromptPoints.map {
                CropStorageDocument.AIData.AIPromptPointData(
                    x: $0.position.x,
                    y: $0.position.y,
                    isPositive: $0.isPositive
                )
            }
            cropData.ai = CropStorageDocument.AIData(
                maskDataBase64: config.aiMaskData?.base64EncodedString(),
                boundingBoxX: config.aiBoundingBox.origin.x,
                boundingBoxY: config.aiBoundingBox.origin.y,
                boundingBoxWidth: config.aiBoundingBox.width,
                boundingBoxHeight: config.aiBoundingBox.height,
                textPrompt: config.aiTextPrompt,
                confidence: config.aiConfidence,
                promptPoints: promptPointsData.isEmpty ? nil : promptPointsData
            )
        }

        // Keyframes
        if config.hasKeyframes {
            cropData.keyframes = config.keyframes.map { kf in
                var kfData = CropStorageDocument.KeyframeData(
                    timestamp: kf.timestamp,
                    interpolation: kf.interpolation.rawValue
                )

                kfData.rectangle = CropStorageDocument.RectangleData(
                    x: Double(kf.cropRect.origin.x),
                    y: Double(kf.cropRect.origin.y),
                    width: Double(kf.cropRect.width),
                    height: Double(kf.cropRect.height)
                )

                kfData.circle = CropStorageDocument.CircleData(
                    centerX: kf.circleCenter.x,
                    centerY: kf.circleCenter.y,
                    radius: kf.circleRadius
                )

                if let pathData = kf.freehandPathData,
                   let maskVertices = try? JSONDecoder().decode([MaskVertex].self, from: pathData) {
                    let vertices = maskVertices.map { mv in
                        CropStorageDocument.VertexData(
                            x: Double(mv.position.x),
                            y: Double(mv.position.y),
                            controlInX: mv.controlIn.map { Double($0.x) },
                            controlInY: mv.controlIn.map { Double($0.y) },
                            controlOutX: mv.controlOut.map { Double($0.x) },
                            controlOutY: mv.controlOut.map { Double($0.y) }
                        )
                    }
                    kfData.freehand = CropStorageDocument.FreehandData(vertices: vertices)
                }

                // Include AI data in keyframe
                if let aiMaskData = kf.aiMaskData, let bbox = kf.aiBoundingBox {
                    let promptPointsData = kf.aiPromptPoints?.map {
                        CropStorageDocument.AIData.AIPromptPointData(
                            x: $0.position.x,
                            y: $0.position.y,
                            isPositive: $0.isPositive
                        )
                    }
                    kfData.ai = CropStorageDocument.AIData(
                        maskDataBase64: aiMaskData.base64EncodedString(),
                        boundingBoxX: bbox.origin.x,
                        boundingBoxY: bbox.origin.y,
                        boundingBoxWidth: bbox.width,
                        boundingBoxHeight: bbox.height,
                        textPrompt: nil,
                        confidence: 0,
                        promptPoints: promptPointsData
                    )
                }

                return kfData
            }
        }

        // Pixel calculations for uncropping
        let outputBounds = CropStorageDocument.OutputBounds(
            cropPixelX: Int(Double(config.cropRect.origin.x) * Double(meta.width)),
            cropPixelY: Int(Double(config.cropRect.origin.y) * Double(meta.height)),
            cropPixelWidth: Int(Double(config.cropRect.width) * Double(meta.width)),
            cropPixelHeight: Int(Double(config.cropRect.height) * Double(meta.height)),
            originalWidth: meta.width,
            originalHeight: meta.height
        )

        return CropStorageDocument(
            version: storageVersion,
            savedAt: Date(),
            source: source,
            crop: cropData,
            outputBounds: outputBounds
        )
    }

    enum StorageError: LocalizedError {
        case invalidPath
        case invalidMetadata

        var errorDescription: String? {
            switch self {
            case .invalidPath:
                return "Invalid storage path"
            case .invalidMetadata:
                return "Invalid video metadata (missing dimensions or frame rate)"
            }
        }
    }
}

// MARK: - Storage Document Structure

struct CropStorageDocument: Codable {
    let version: String
    let savedAt: Date
    let source: SourceInfo
    let crop: CropData
    let outputBounds: OutputBounds

    struct SourceInfo: Codable {
        let filePath: String
        let fileName: String
        let width: Int
        let height: Int
        let duration: Double
        let frameRate: Double
        let codec: String
        let isHDR: Bool
        let colorSpace: String?
        let bitDepth: Int
        let bitRate: Int64
    }

    struct CropData: Codable {
        let mode: String
        var rectangle: RectangleData?
        var circle: CircleData?
        var freehand: FreehandData?
        var ai: AIData?
        var keyframes: [KeyframeData]?

        init(mode: String) {
            self.mode = mode
        }
    }

    struct RectangleData: Codable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    struct CircleData: Codable {
        let centerX: Double
        let centerY: Double
        let radius: Double
    }

    struct FreehandData: Codable {
        let vertices: [VertexData]
    }

    struct AIData: Codable {
        let maskDataBase64: String?
        let boundingBoxX: Double
        let boundingBoxY: Double
        let boundingBoxWidth: Double
        let boundingBoxHeight: Double
        let textPrompt: String?
        let confidence: Double
        let promptPoints: [AIPromptPointData]?

        struct AIPromptPointData: Codable {
            let x: Double
            let y: Double
            let isPositive: Bool
        }
    }

    struct VertexData: Codable {
        let x: Double
        let y: Double
        var controlInX: Double?
        var controlInY: Double?
        var controlOutX: Double?
        var controlOutY: Double?

        init(x: Double, y: Double, controlInX: Double? = nil, controlInY: Double? = nil, controlOutX: Double? = nil, controlOutY: Double? = nil) {
            self.x = x
            self.y = y
            self.controlInX = controlInX
            self.controlInY = controlInY
            self.controlOutX = controlOutX
            self.controlOutY = controlOutY
        }
    }

    struct KeyframeData: Codable {
        let timestamp: Double
        let interpolation: String
        var rectangle: RectangleData?
        var circle: CircleData?
        var freehand: FreehandData?
        var ai: AIData?

        init(timestamp: Double, interpolation: String) {
            self.timestamp = timestamp
            self.interpolation = interpolation
        }
    }

    /// Pre-calculated pixel values for easy uncropping
    struct OutputBounds: Codable {
        let cropPixelX: Int
        let cropPixelY: Int
        let cropPixelWidth: Int
        let cropPixelHeight: Int
        let originalWidth: Int
        let originalHeight: Int

        /// FFmpeg crop filter string
        var ffmpegCropFilter: String {
            "crop=\(cropPixelWidth):\(cropPixelHeight):\(cropPixelX):\(cropPixelY)"
        }

        /// FFmpeg pad filter to restore original dimensions
        var ffmpegUncropFilter: String {
            "pad=\(originalWidth):\(originalHeight):\(cropPixelX):\(cropPixelY)"
        }
    }
}
