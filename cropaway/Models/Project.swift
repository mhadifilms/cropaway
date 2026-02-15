//
//  Project.swift
//  Cropaway
//
//  Top-level workspace container for media assets and sequences.
//

import Foundation
import SwiftUI
import Combine

/// Top-level workspace containing media pool and sequences
@MainActor
final class Project: ObservableObject {
    // MARK: - Properties
    
    let id: UUID
    @Published var name: String
    let dateCreated: Date
    @Published var dateModified: Date
    
    // Media pool
    @Published var mediaAssets: [MediaAsset] = []
    
    // Sequences
    @Published var sequences: [Sequence] = []
    @Published var selectedSequence: Sequence?
    
    // MARK: - Initialization
    
    init(name: String = "Untitled Project", id: UUID = UUID()) {
        self.id = id
        self.name = name
        self.dateCreated = Date()
        self.dateModified = Date()
    }
    
    // MARK: - Media Management
    
    func addMediaAsset(_ asset: MediaAsset) {
        // Prevent duplicates by URL
        if mediaAssets.contains(where: { $0.sourceURL == asset.sourceURL }) {
            return
        }
        mediaAssets.append(asset)
        dateModified = Date()
    }
    
    func removeMediaAsset(_ asset: MediaAsset) {
        // Check if asset is used in any sequence
        let isUsed = sequences.contains { sequence in
            sequence.clips.contains { $0.mediaAsset.id == asset.id }
        }
        
        if isUsed {
            // Don't remove if in use (or show warning in real implementation)
            return
        }
        
        mediaAssets.removeAll { $0.id == asset.id }
        dateModified = Date()
    }
    
    func getMediaAsset(byId id: UUID) -> MediaAsset? {
        return mediaAssets.first { $0.id == id }
    }
    
    // MARK: - Sequence Management
    
    func createSequence(name: String) -> Sequence {
        let sequence = Sequence(name: name)
        sequences.append(sequence)
        selectedSequence = sequence
        dateModified = Date()
        return sequence
    }
    
    func removeSequence(_ sequence: Sequence) {
        sequences.removeAll { $0.id == sequence.id }
        if selectedSequence?.id == sequence.id {
            selectedSequence = sequences.first
        }
        dateModified = Date()
    }
    
    func getSequence(byId id: UUID) -> Sequence? {
        return sequences.first { $0.id == id }
    }
}

// MARK: - Codable

extension Project {
    struct Snapshot: Codable {
        let id: UUID
        let name: String
        let dateCreated: Date
        let dateModified: Date
        let mediaAssetSnapshots: [MediaAsset.Snapshot]
        let sequenceSnapshots: [Sequence.Snapshot]
        let selectedSequenceId: UUID?
    }
    
    func snapshot() -> Snapshot {
        return Snapshot(
            id: id,
            name: name,
            dateCreated: dateCreated,
            dateModified: dateModified,
            mediaAssetSnapshots: mediaAssets.map { $0.snapshot() },
            sequenceSnapshots: sequences.map { $0.snapshot(mediaAssets: mediaAssets) },
            selectedSequenceId: selectedSequence?.id
        )
    }
    
    static func fromSnapshot(_ snapshot: Snapshot) -> Project {
        let project = Project(name: snapshot.name, id: snapshot.id)
        
        // Restore media assets
        project.mediaAssets = snapshot.mediaAssetSnapshots.map { MediaAsset.fromSnapshot($0) }
        
        // Restore sequences (need media asset references)
        project.sequences = snapshot.sequenceSnapshots.map { seqSnapshot in
            Sequence.fromSnapshot(seqSnapshot, mediaAssets: project.mediaAssets)
        }
        
        // Restore selected sequence
        if let selectedId = snapshot.selectedSequenceId {
            project.selectedSequence = project.getSequence(byId: selectedId)
        }
        
        return project
    }
}
