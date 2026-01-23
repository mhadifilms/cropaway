//
//  AVExtensions.swift
//  cropaway
//

import Foundation
import AVFoundation
import CoreMedia

extension CMTime {
    var seconds: Double {
        CMTimeGetSeconds(self)
    }

    var displayString: String {
        let totalSeconds = Int(seconds)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

extension Double {
    var timeDisplayString: String {
        let totalSeconds = Int(self)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}

extension AVAsset {
    var videoTrack: AVAssetTrack? {
        get async {
            try? await loadTracks(withMediaType: .video).first
        }
    }

    var audioTrack: AVAssetTrack? {
        get async {
            try? await loadTracks(withMediaType: .audio).first
        }
    }
}

extension FourCharCode {
    var fourCCString: String {
        let bytes: [CChar] = [
            CChar((self >> 24) & 0xFF),
            CChar((self >> 16) & 0xFF),
            CChar((self >> 8) & 0xFF),
            CChar(self & 0xFF),
            0
        ]
        return String(cString: bytes)
    }
}

extension AVVideoCodecType {
    init?(fourCC: FourCharCode) {
        let string = fourCC.fourCCString
        switch string {
        case "avc1", "avc2", "avc3", "avc4":
            self = .h264
        case "hvc1", "hev1":
            self = .hevc
        case "ap4x":
            // ProRes 4444 XQ - map to ProRes 4444 (highest quality available in AVFoundation)
            self = .proRes4444
        case "ap4h":
            self = .proRes4444
        case "apch":
            self = .proRes422HQ
        case "apcn":
            self = .proRes422
        case "apcs":
            self = .proRes422LT
        case "apco":
            self = .proRes422Proxy
        default:
            return nil
        }
    }

    var displayName: String {
        switch self {
        case .h264:
            return "H.264"
        case .hevc:
            return "H.265/HEVC"
        case .proRes4444:
            return "ProRes 4444"
        case .proRes422HQ:
            return "ProRes 422 HQ"
        case .proRes422:
            return "ProRes 422"
        case .proRes422LT:
            return "ProRes 422 LT"
        case .proRes422Proxy:
            return "ProRes 422 Proxy"
        default:
            return rawValue
        }
    }
}
