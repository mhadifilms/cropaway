//
//  ExportConfiguration.swift
//  cropaway
//

import Combine
import Foundation
import AVFoundation

final class ExportConfiguration: ObservableObject {
    @Published var preserveWidth: Bool = true
    @Published var enableAlphaChannel: Bool = false
    @Published var outputURL: URL?

    init() {}

    var outputCodec: AVVideoCodecType {
        if enableAlphaChannel {
            return .proRes4444
        } else {
            // Will be determined by source codec
            return .proRes422HQ
        }
    }

    var requiresProResExport: Bool {
        enableAlphaChannel
    }

    var shouldMatchSourceCodec: Bool {
        !enableAlphaChannel
    }

    var outputFileExtension: String {
        "mov"
    }
}
