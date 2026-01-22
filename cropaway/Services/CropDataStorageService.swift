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

    private init() {}

    // MARK: - Public API

    /// Save crop data for a video (creates timestamped file)
    func save(video: VideoItem) throws {
        let document = createDocument(from: video)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(document)
        let fileURL = try createStorageURL(for: video.sourceURL)
        try data.write(to: fileURL)

        print("Crop data saved to: \(fileURL.path)")
    }

    /// Load most recent crop data for a video (returns nil if not found)
    func load(for sourceURL: URL) -> CropStorageDocument? {
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

                return kf
            }
        }
    }

    /// List all crop data files for a video
    func listFiles(for sourceURL: URL) -> [URL] {
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

    /// Delete all crop data for a video
    func deleteAll(for sourceURL: URL) {
        for file in listFiles(for: sourceURL) {
            try? fileManager.removeItem(at: file)
        }
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

    enum StorageError: Error {
        case invalidPath
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
