//
//  VideoItem.swift
//  cropaway
//

import Combine
import Foundation
import AVFoundation
import AppKit

final class VideoItem: Identifiable, ObservableObject, Hashable {
    let id: UUID
    let sourceURL: URL
    @Published var fileName: String
    let dateAdded: Date

    @Published var thumbnail: NSImage?
    @Published var metadata: VideoMetadata
    @Published var cropConfiguration: CropConfiguration

    @Published var lastExportURL: URL?
    @Published var lastExportDate: Date?

    @Published var isLoading: Bool = true
    @Published var loadError: String?

    private var asset: AVURLAsset?
    private var cancellables = Set<AnyCancellable>()
    private var saveWorkItem: DispatchWorkItem?

    init(sourceURL: URL) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.fileName = sourceURL.deletingPathExtension().lastPathComponent
        self.dateAdded = Date()
        self.metadata = VideoMetadata()
        self.cropConfiguration = CropConfiguration()

        setupAutoSave()
        loadSavedCropData()
    }

    static func == (lhs: VideoItem, rhs: VideoItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    /// Returns true if any crop changes have been made
    var hasCropChanges: Bool {
        cropConfiguration.hasCropChanges
    }

    func getAsset() -> AVURLAsset {
        if let asset = self.asset {
            return asset
        }
        let asset = AVURLAsset(url: sourceURL)
        self.asset = asset
        return asset
    }

    @MainActor
    func generateThumbnail() async {
        let asset = getAsset()
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 200, height: 200)

        do {
            let time = CMTime(seconds: 0, preferredTimescale: 600)
            let cgImage = try await imageGenerator.image(at: time).image
            self.thumbnail = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            // Use placeholder
            self.thumbnail = NSImage(systemSymbolName: "film", accessibilityDescription: "Video")
        }
    }

    // MARK: - Auto-Save

    private func setupAutoSave() {
        // Observe all crop configuration changes
        cropConfiguration.objectWillChange
            .debounce(for: .milliseconds(500), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleSave()
            }
            .store(in: &cancellables)
    }

    private func scheduleSave() {
        // Cancel previous save
        saveWorkItem?.cancel()

        // Schedule new save
        saveWorkItem = DispatchWorkItem { [weak self] in
            self?.saveCropData()
        }

        DispatchQueue.global(qos: .utility).asyncAfter(
            deadline: .now() + 0.3,
            execute: saveWorkItem!
        )
    }

    /// Manually trigger save (e.g., after export)
    func saveCropData() {
        guard hasCropChanges else { return }

        do {
            try CropDataStorageService.shared.save(video: self)
        } catch {
            print("Failed to save crop data: \(error)")
        }
    }

    /// Load previously saved crop data
    private func loadSavedCropData() {
        if let document = CropDataStorageService.shared.load(for: sourceURL) {
            CropDataStorageService.shared.apply(document, to: self)
            print("Loaded saved crop data for: \(sourceURL.lastPathComponent)")
        }
    }

    /// Clear all saved crop data
    func clearSavedCropData() {
        CropDataStorageService.shared.deleteAll(for: sourceURL)
    }
}
