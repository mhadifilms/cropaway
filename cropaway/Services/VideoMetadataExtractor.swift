//
//  VideoMetadataExtractor.swift
//  cropaway
//

import Foundation
import AVFoundation
import CoreMedia

final class VideoMetadataExtractor: Sendable {

    @MainActor
    func extractMetadata(for video: VideoItem) async throws {
        let asset = video.getAsset()
        let metadata = video.metadata

        // Load video track
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw MetadataError.noVideoTrack
        }

        // Duration
        let duration = try await asset.load(.duration)
        metadata.duration = duration.seconds
        metadata.timeScale = duration.timescale

        // Dimensions
        let naturalSize = try await videoTrack.load(.naturalSize)
        let preferredTransform = try await videoTrack.load(.preferredTransform)
        let transformedSize = naturalSize.applying(preferredTransform)

        metadata.width = Int(abs(transformedSize.width))
        metadata.height = Int(abs(transformedSize.height))
        if metadata.height > 0 {
            metadata.displayAspectRatio = Double(metadata.width) / Double(metadata.height)
        }

        // Frame rate
        let nominalFrameRate = try await videoTrack.load(.nominalFrameRate)
        metadata.nominalFrameRate = Double(nominalFrameRate)
        metadata.frameRate = Double(nominalFrameRate)

        // Codec info from format descriptions
        let formatDescriptions = try await videoTrack.load(.formatDescriptions)
        if let formatDesc = formatDescriptions.first {
            extractCodecInfo(from: formatDesc, to: metadata)
        }

        // Estimated bit rate
        let estimatedDataRate = try await videoTrack.load(.estimatedDataRate)
        metadata.bitRate = Int64(estimatedDataRate)

        // Audio track info
        if let audioTrack = try await asset.loadTracks(withMediaType: .audio).first {
            await extractAudioInfo(from: audioTrack, to: metadata)
        }

        // Container format
        metadata.containerFormat = video.sourceURL.pathExtension.lowercased()
    }

    @MainActor
    private func extractCodecInfo(from formatDesc: CMFormatDescription, to metadata: VideoMetadata) {
        let mediaSubType = CMFormatDescriptionGetMediaSubType(formatDesc)

        metadata.codecFourCC = mediaSubType
        metadata.codecType = mediaSubType.fourCCString

        // Codec description
        switch mediaSubType.fourCCString {
        case "avc1", "avc2", "avc3", "avc4":
            metadata.codecDescription = "H.264/AVC"
        case "hvc1", "hev1":
            metadata.codecDescription = "H.265/HEVC"
        case "ap4x":
            metadata.codecDescription = "Apple ProRes 4444 XQ"
        case "ap4h", "ap4c":
            metadata.codecDescription = "Apple ProRes 4444"
        case "apch":
            metadata.codecDescription = "Apple ProRes 422 HQ"
        case "apcn":
            metadata.codecDescription = "Apple ProRes 422"
        case "apcs":
            metadata.codecDescription = "Apple ProRes 422 LT"
        case "apco":
            metadata.codecDescription = "Apple ProRes 422 Proxy"
        default:
            metadata.codecDescription = mediaSubType.fourCCString
        }

        // Extract extensions for color info
        guard let extensions = CMFormatDescriptionGetExtensions(formatDesc) as? [String: Any] else { return }

        // Color primaries
        metadata.colorPrimaries = extensions[kCVImageBufferColorPrimariesKey as String] as? String
        metadata.transferFunction = extensions[kCVImageBufferTransferFunctionKey as String] as? String
        metadata.colorMatrix = extensions[kCVImageBufferYCbCrMatrixKey as String] as? String

        // Bit depth (8, 10, 12, or 16 for ProRes, DPX, etc.)
        if let bitsPerComponent = extensions["BitsPerComponent"] as? Int {
            metadata.bitDepth = bitsPerComponent
        }

        // Detect HDR
        let isHDR = metadata.transferFunction?.contains("2084") == true ||
                    metadata.transferFunction?.contains("PQ") == true ||
                    metadata.transferFunction?.contains("HLG") == true
        metadata.isHDR = isHDR

        if isHDR {
            if metadata.transferFunction?.contains("2084") == true || metadata.transferFunction?.contains("PQ") == true {
                metadata.hdrFormat = "HDR10"
            } else if metadata.transferFunction?.contains("HLG") == true {
                metadata.hdrFormat = "HLG"
            }
        }
    }

    @MainActor
    private func extractAudioInfo(from audioTrack: AVAssetTrack, to metadata: VideoMetadata) async {
        let formatDescriptions = try? await audioTrack.load(.formatDescriptions)

        guard let formatDesc = formatDescriptions?.first else {
            metadata.hasAudio = false
            return
        }

        metadata.hasAudio = true

        if let audioStreamBasicDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc) {
            let asbd = audioStreamBasicDescription.pointee
            metadata.audioSampleRate = asbd.mSampleRate
            metadata.audioChannels = Int(asbd.mChannelsPerFrame)
        }

        // Codec type
        let mediaSubType = CMFormatDescriptionGetMediaSubType(formatDesc)
        switch mediaSubType.fourCCString {
        case "aac ":
            metadata.audioCodec = "AAC"
        case "lpcm":
            metadata.audioCodec = "Linear PCM"
        case "ac-3":
            metadata.audioCodec = "AC-3"
        case "ec-3":
            metadata.audioCodec = "E-AC-3"
        default:
            metadata.audioCodec = mediaSubType.fourCCString
        }

        // Audio bit rate
        if let estimatedDataRate = try? await audioTrack.load(.estimatedDataRate) {
            metadata.audioBitRate = Int64(estimatedDataRate)
        }
    }

    enum MetadataError: LocalizedError {
        case noVideoTrack
        case extractionFailed(String)

        var errorDescription: String? {
            switch self {
            case .noVideoTrack:
                return "No video track found in file"
            case .extractionFailed(let reason):
                return "Failed to extract metadata: \(reason)"
            }
        }
    }
}
