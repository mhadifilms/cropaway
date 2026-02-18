//
//  TimelineStorageService.swift
//  cropaway
//
//  Service for saving/loading timeline sequences to Application Support

import Foundation

/// Service for persisting timeline data to disk
final class TimelineStorageService {
    static let shared = TimelineStorageService()
    
    private let fileManager = FileManager.default
    private let storageVersion = "2.0"  // Updated for multi-track support
    
    /// Serial queue for thread-safe file operations
    private let fileQueue = DispatchQueue(label: "com.cropaway.timeline-storage", qos: .userInitiated)
    
    private init() {}
    
    /// Application Support folder for timelines: ~/Library/Application Support/Cropaway/timelines/
    private var timelinesDirectory: URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base
            .appendingPathComponent("Cropaway", isDirectory: true)
            .appendingPathComponent("timelines", isDirectory: true)
    }
    
    // MARK: - Public API
    
    /// Save a timeline to disk
    func save(_ timeline: Timeline) throws {
        let document = TimelineDocument(timeline: timeline)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(document)
        
        // Thread-safe file write
        var writeError: Error?
        var savedURL: URL?
        fileQueue.sync {
            do {
                let fileURL = try createStorageURL(for: timeline)
                try data.write(to: fileURL)
                savedURL = fileURL
            } catch {
                writeError = error
            }
        }
        
        if let error = writeError {
            throw error
        }
        
        if let url = savedURL {
            print("✅ Timeline saved: \(url.lastPathComponent)")
        }
    }
    
    /// Load a specific timeline by ID
    func load(id: UUID) -> Timeline? {
        return fileQueue.sync {
            let folder = timelinesDirectory
            guard fileManager.fileExists(atPath: folder.path) else { return nil }
            
            let fileURL = folder.appendingPathComponent("\(id.uuidString).json")
            guard fileManager.fileExists(atPath: fileURL.path) else { return nil }
            
            do {
                let data = try Data(contentsOf: fileURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let document = try decoder.decode(TimelineDocument.self, from: data)
                
                // Migrate timeline if needed (old format to multi-track)
                let timeline = document.timeline
                if timeline.needsMigration {
                    print("🔄 Migrating timeline '\(timeline.name)' to multi-track format...")
                    Task { @MainActor in
                        DataMigrationService.migrateTimeline(timeline)
                        // Auto-save migrated timeline
                        try? self.save(timeline)
                    }
                }
                
                print("✅ Timeline loaded: \(timeline.name)")
                return timeline
            } catch {
                print("⚠️ Failed to load timeline \(id): \(error)")
                return nil
            }
        }
    }
    
    /// Load all saved timelines
    func loadAll() -> [Timeline] {
        return fileQueue.sync {
            let folder = timelinesDirectory
            guard fileManager.fileExists(atPath: folder.path) else { return [] }
            
            do {
                let contents = try fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
                let jsonFiles = contents.filter { $0.pathExtension == "json" }
                
                var timelines: [Timeline] = []
                for fileURL in jsonFiles {
                    do {
                        let data = try Data(contentsOf: fileURL)
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        let document = try decoder.decode(TimelineDocument.self, from: data)
                        
                        let timeline = document.timeline
                        
                        // Migrate timeline if needed (old format to multi-track)
                        if timeline.needsMigration {
                            print("🔄 Migrating timeline '\(timeline.name)' to multi-track format...")
                            Task { @MainActor in
                                DataMigrationService.migrateTimeline(timeline)
                                // Auto-save migrated timeline
                                try? self.save(timeline)
                            }
                        }
                        
                        timelines.append(timeline)
                    } catch {
                        print("⚠️ Failed to load timeline from \(fileURL.lastPathComponent): \(error)")
                    }
                }
                
                // Sort by most recently modified
                timelines.sort { $0.dateModified > $1.dateModified }
                
                print("✅ Loaded \(timelines.count) timeline(s)")
                return timelines
            } catch {
                print("⚠️ Failed to read timelines directory: \(error)")
                return []
            }
        }
    }
    
    /// Delete a timeline
    func delete(_ timeline: Timeline) throws {
        var deleteError: Error?
        fileQueue.sync {
            do {
                let fileURL = timelinesDirectory.appendingPathComponent("\(timeline.id.uuidString).json")
                if fileManager.fileExists(atPath: fileURL.path) {
                    try fileManager.removeItem(at: fileURL)
                    print("✅ Timeline deleted: \(timeline.name)")
                }
            } catch {
                deleteError = error
            }
        }
        
        if let error = deleteError {
            throw error
        }
    }
    
    /// Export a timeline to a user-chosen location
    func export(_ timeline: Timeline, to url: URL) throws {
        let document = TimelineDocument(timeline: timeline)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(document)
        try data.write(to: url)
        
        print("✅ Timeline exported to: \(url.path)")
    }
    
    /// Import a timeline from a file
    func importTimeline(from url: URL) throws -> Timeline {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let document = try decoder.decode(TimelineDocument.self, from: data)
        
        let timeline = document.timeline
        
        // Migrate timeline if needed (old format to multi-track)
        if timeline.needsMigration {
            print("🔄 Migrating imported timeline '\(timeline.name)' to multi-track format...")
            Task { @MainActor in
                DataMigrationService.migrateTimeline(timeline)
            }
        }
        
        // Save to Application Support
        try save(timeline)
        
        print("✅ Timeline imported: \(timeline.name)")
        return timeline
    }
    
    // MARK: - Private Helpers
    
    private func createStorageURL(for timeline: Timeline) throws -> URL {
        let folder = timelinesDirectory
        
        // Create directory if needed
        if !fileManager.fileExists(atPath: folder.path) {
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        
        return folder.appendingPathComponent("\(timeline.id.uuidString).json")
    }
}

// MARK: - Timeline Document

/// Wrapper document for timeline persistence with metadata
struct TimelineDocument: Codable {
    let version: String
    let timeline: Timeline
    let savedAt: Date
    
    init(timeline: Timeline, version: String = "2.0") {
        self.version = version
        self.timeline = timeline
        self.savedAt = Date()
    }
}
