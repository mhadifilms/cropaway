//
//  TransitionCompositionInstruction.swift
//  cropaway
//

import Foundation
import AVFoundation

/// Custom video composition instruction for transitions
/// Passed to TransitionVideoCompositor to specify how to blend frames
final class TransitionCompositionInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    
    var timeRange: CMTimeRange
    var enablePostProcessing: Bool = false
    var containsTweening: Bool = true
    var requiredSourceTrackIDs: [NSValue]?
    var passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid
    
    /// Track ID of outgoing clip (fade from)
    let fromTrackID: CMPersistentTrackID
    
    /// Track ID of incoming clip (fade to)
    let toTrackID: CMPersistentTrackID
    
    /// Type of transition to render
    let transitionType: TransitionType
    
    init(
        timeRange: CMTimeRange,
        fromTrackID: CMPersistentTrackID,
        toTrackID: CMPersistentTrackID,
        transitionType: TransitionType
    ) {
        self.timeRange = timeRange
        self.fromTrackID = fromTrackID
        self.toTrackID = toTrackID
        self.transitionType = transitionType
        self.requiredSourceTrackIDs = [
            NSNumber(value: fromTrackID),
            NSNumber(value: toTrackID)
        ]
        super.init()
    }
}
