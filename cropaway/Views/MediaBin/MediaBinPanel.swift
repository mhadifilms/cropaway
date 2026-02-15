//
//  MediaBinPanel.swift
//  Cropaway
//
//  Displays media assets in a grid for drag-and-drop to timeline.
//

import SwiftUI
import UniformTypeIdentifiers

struct MediaBinPanel: View {
    @EnvironmentObject var projectVM: ProjectViewModel
    @Binding var isExpanded: Bool
    
    private let columns = [
        GridItem(.adaptive(minimum: 120, maximum: 150), spacing: 12)
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            MediaBinHeaderView(isExpanded: $isExpanded)
            
            if isExpanded {
                Divider()
                
                // Media grid or empty state
                if project.mediaAssets.isEmpty {
                    emptyState
                } else {
                    mediaGrid
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("No Media")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Import video files to get started")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button(action: { importMedia() }) {
                Label("Import Media", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
    }
    
    private var mediaGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(project.mediaAssets) { asset in
                    MediaAssetThumbnailView(asset: asset)
                        .environmentObject(projectVM)
                }
            }
            .padding(12)
        }
        .frame(height: isExpanded ? 200 : 0)
    }
    
    private var project: Project {
        projectVM.project
    }
    
    private func importMedia() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.movie, .video, .quickTimeMovie, .mpeg4Movie]
        
        if panel.runModal() == .OK {
            Task {
                await projectVM.addMediaAssets(from: panel.urls)
            }
        }
    }
}

// MARK: - Media Bin Header

struct MediaBinHeaderView: View {
    @Binding var isExpanded: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 11, weight: .semibold))
            
            Text("Media Bin")
                .font(.system(size: 12, weight: .semibold))
            
            Spacer()
            
            Button(action: {}) {
                Image(systemName: "plus")
                    .font(.system(size: 11))
            }
            .buttonStyle(.borderless)
            .help("Import Media")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
    }
}

// MARK: - Media Asset Thumbnail

struct MediaAssetThumbnailView: View {
    @ObservedObject var asset: MediaAsset
    @EnvironmentObject var projectVM: ProjectViewModel
    @State private var isDragging = false
    
    var body: some View {
        VStack(spacing: 4) {
            // Thumbnail
            Group {
                if let thumbnail = asset.thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if asset.isLoading {
                    ProgressView()
                        .scaleEffect(0.5)
                } else {
                    Image(systemName: "film")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 120, height: 68)
            .background(Color.black.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay {
                if asset.loadError != nil {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundColor(.red)
                }
            }
            
            // Name and duration
            VStack(alignment: .leading, spacing: 2) {
                Text(asset.fileName)
                    .font(.system(size: 11))
                    .lineLimit(1)
                    .truncationMode(.middle)
                
                if asset.metadata.duration > 0 {
                    Text(formatDuration(asset.metadata.duration))
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 120)
        .padding(6)
        .background(isDragging ? Color.accentColor.opacity(0.2) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .onDrag {
            isDragging = true
            // Create drag data with asset ID
            let provider = NSItemProvider(object: asset.id.uuidString as NSString)
            provider.suggestedName = asset.fileName
            return provider
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

struct MediaBinPanel_Previews: PreviewProvider {
    static var previews: some View {
        let projectVM = ProjectViewModel()
        
        return MediaBinPanel(isExpanded: .constant(true))
            .environmentObject(projectVM)
            .frame(height: 250)
    }
}
