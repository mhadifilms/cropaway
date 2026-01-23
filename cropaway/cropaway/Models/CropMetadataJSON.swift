//
//  CropMetadataJSON.swift
//  cropaway
//

import Foundation

struct CropMetadataDocument: Codable {
    let version: String
    let generatedAt: Date
    let sourceFile: SourceFileInfo
    let cropData: CropData
    let exportSettings: ExportSettingsInfo

    init(
        sourceFile: SourceFileInfo,
        cropData: CropData,
        exportSettings: ExportSettingsInfo
    ) {
        self.version = "1.0"
        self.generatedAt = Date()
        self.sourceFile = sourceFile
        self.cropData = cropData
        self.exportSettings = exportSettings
    }

    struct SourceFileInfo: Codable {
        let fileName: String
        let originalWidth: Int
        let originalHeight: Int
        let duration: Double
        let frameRate: Double
        let codec: String
        let isHDR: Bool
        let colorSpace: String?
    }

    struct CropData: Codable {
        let mode: String
        let isAnimated: Bool
        let staticCrop: StaticCropInfo?
        let keyframes: [KeyframeInfo]?
    }

    struct StaticCropInfo: Codable {
        // Rectangle mode (normalized 0-1)
        let rectX: Double?
        let rectY: Double?
        let rectWidth: Double?
        let rectHeight: Double?

        // Edge mode (normalized 0-1)
        let edgeTop: Double?
        let edgeLeft: Double?
        let edgeBottom: Double?
        let edgeRight: Double?

        // Circle mode (normalized)
        let circleCenterX: Double?
        let circleCenterY: Double?
        let circleRadius: Double?

        // Freehand mode (SVG path for interoperability)
        let freehandPathSVG: String?

        // AI mode (bounding box and prompt info)
        let aiBoundingBoxX: Double?
        let aiBoundingBoxY: Double?
        let aiBoundingBoxWidth: Double?
        let aiBoundingBoxHeight: Double?
        let aiTextPrompt: String?
        let aiConfidence: Double?

        init(
            rectX: Double? = nil,
            rectY: Double? = nil,
            rectWidth: Double? = nil,
            rectHeight: Double? = nil,
            edgeTop: Double? = nil,
            edgeLeft: Double? = nil,
            edgeBottom: Double? = nil,
            edgeRight: Double? = nil,
            circleCenterX: Double? = nil,
            circleCenterY: Double? = nil,
            circleRadius: Double? = nil,
            freehandPathSVG: String? = nil,
            aiBoundingBoxX: Double? = nil,
            aiBoundingBoxY: Double? = nil,
            aiBoundingBoxWidth: Double? = nil,
            aiBoundingBoxHeight: Double? = nil,
            aiTextPrompt: String? = nil,
            aiConfidence: Double? = nil
        ) {
            self.rectX = rectX
            self.rectY = rectY
            self.rectWidth = rectWidth
            self.rectHeight = rectHeight
            self.edgeTop = edgeTop
            self.edgeLeft = edgeLeft
            self.edgeBottom = edgeBottom
            self.edgeRight = edgeRight
            self.circleCenterX = circleCenterX
            self.circleCenterY = circleCenterY
            self.circleRadius = circleRadius
            self.freehandPathSVG = freehandPathSVG
            self.aiBoundingBoxX = aiBoundingBoxX
            self.aiBoundingBoxY = aiBoundingBoxY
            self.aiBoundingBoxWidth = aiBoundingBoxWidth
            self.aiBoundingBoxHeight = aiBoundingBoxHeight
            self.aiTextPrompt = aiTextPrompt
            self.aiConfidence = aiConfidence
        }
    }

    struct KeyframeInfo: Codable {
        let timestamp: Double
        let interpolation: String
        let crop: StaticCropInfo
    }

    struct ExportSettingsInfo: Codable {
        let preserveWidth: Bool
        let enableAlphaChannel: Bool
        let outputCodec: String
        let outputWidth: Int
        let outputHeight: Int
    }
}
