//
//  VideoMetadata.swift
//  cropaway
//

import Combine
import Foundation
import AVFoundation
import CoreMedia

final class VideoMetadata: ObservableObject {
    // Dimensions
    @Published var width: Int = 0
    @Published var height: Int = 0
    @Published var displayAspectRatio: Double = 1.0

    // Temporal
    @Published var duration: Double = 0
    @Published var frameRate: Double = 0
    @Published var nominalFrameRate: Double = 0
    @Published var timeScale: Int32 = 600

    // Codec & Format
    @Published var codecType: String = ""
    @Published var codecFourCC: FourCharCode = 0
    @Published var codecDescription: String = ""
    @Published var profileLevel: String?
    @Published var bitRate: Int64 = 0
    @Published var bitDepth: Int = 8

    // Color
    @Published var colorPrimaries: String?
    @Published var transferFunction: String?
    @Published var colorMatrix: String?
    @Published var isHDR: Bool = false
    @Published var hdrFormat: String?

    // Audio
    @Published var audioCodec: String?
    @Published var audioSampleRate: Double?
    @Published var audioChannels: Int?
    @Published var audioBitRate: Int64?
    @Published var hasAudio: Bool = false

    // Container
    @Published var containerFormat: String = "mov"

    init() {}

    var colorSpaceDescription: String? {
        guard let primaries = colorPrimaries else { return nil }

        if primaries.contains("2020") {
            return "Rec. 2020"
        } else if primaries.contains("709") {
            return "Rec. 709"
        } else if primaries.contains("P3") {
            return "Display P3"
        }
        return primaries
    }

    var hdrDescription: String? {
        guard isHDR else { return nil }

        if let transfer = transferFunction {
            if transfer.contains("2084") || transfer.contains("PQ") {
                return "HDR10"
            } else if transfer.contains("HLG") {
                return "HLG"
            }
        }
        return "HDR"
    }
}
