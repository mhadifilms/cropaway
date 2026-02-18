//
//  InspectorViewModel.swift
//  cropaway
//
//  Created by Claude Code for Inspector Panel
//

import Foundation
import SwiftUI

@MainActor
@Observable
final class InspectorViewModel {
    // MARK: - Selected Clip
    var selectedClip: TimelineClip?
    
    // MARK: - Transform Properties (synced from clip)
    var scale: CGFloat = 1.0 {
        didSet {
            selectedClip?.scale = scale
        }
    }
    
    var positionX: Double = 0.5 {
        didSet {
            selectedClip?.positionX = positionX
        }
    }
    
    var positionY: Double = 0.5 {
        didSet {
            selectedClip?.positionY = positionY
        }
    }
    
    var rotation: Double = 0.0 {
        didSet {
            selectedClip?.rotation = rotation
        }
    }
    
    var flipHorizontal: Bool = false {
        didSet {
            selectedClip?.flipHorizontal = flipHorizontal
        }
    }
    
    var flipVertical: Bool = false {
        didSet {
            selectedClip?.flipVertical = flipVertical
        }
    }
    
    var opacity: Double = 1.0 {
        didSet {
            selectedClip?.opacity = opacity
        }
    }
    
    // PHASE 9: Audio Properties
    var volume: Float = 1.0 {
        didSet {
            selectedClip?.volume = volume
        }
    }
    
    var isMuted: Bool = false {
        didSet {
            selectedClip?.isMuted = isMuted
        }
    }
    
    // MARK: - Crop Properties
    var cropMode: CropMode {
        selectedClip?.cropConfiguration?.mode ?? .rectangle
    }
    
    // MARK: - Binding to Clip
    
    /// Bind inspector to a timeline clip
    func bind(to clip: TimelineClip?) {
        guard let clip = clip else {
            selectedClip = nil
            resetToDefaults()
            return
        }
        
        selectedClip = clip
        
        // Load transform properties from clip
        scale = clip.scale
        positionX = clip.positionX
        positionY = clip.positionY
        rotation = clip.rotation
        flipHorizontal = clip.flipHorizontal
        flipVertical = clip.flipVertical
        opacity = clip.opacity
        
        // PHASE 9: Load audio properties from clip
        volume = clip.volume
        isMuted = clip.isMuted
    }
    
    /// Reset all properties to defaults
    private func resetToDefaults() {
        scale = 1.0
        positionX = 0.5
        positionY = 0.5
        rotation = 0.0
        flipHorizontal = false
        flipVertical = false
        opacity = 1.0
        volume = 1.0
        isMuted = false
    }
    
    // MARK: - Reset Actions
    
    func resetScale() {
        scale = 1.0
    }
    
    func resetPosition() {
        positionX = 0.5
        positionY = 0.5
    }
    
    func resetRotation() {
        rotation = 0.0
    }
    
    func resetTransform() {
        resetScale()
        resetPosition()
        resetRotation()
        flipHorizontal = false
        flipVertical = false
    }
}
