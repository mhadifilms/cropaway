//
//  ProjectSidebarView.swift
//  cropaway
//
//  Created by Claude Code for Project Sidebar
//

import SwiftUI
import UniformTypeIdentifiers

enum SidebarTab: String, CaseIterable {
    case sequences = "Sequences"
    case mediaBin = "Media Bin"
    
    var icon: String {
        switch self {
        case .sequences: return "film.stack"
        case .mediaBin: return "photo.stack.fill"
        }
    }
}

struct ProjectSidebarView: View {
    @Bindable var projectViewModel: ProjectViewModel
    @Bindable var timelineViewModel: TimelineViewModel
    @State private var selectedTab: SidebarTab = .sequences
    @State private var showingImportDialog = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Tab selector with Liquid Glass
            Picker("", selection: $selectedTab) {
                ForEach(SidebarTab.allCases, id: \.self) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(8)
            .background(Color(nsColor: .windowBackgroundColor))
            .overlay(
                Divider(),
                alignment: .bottom
            )
            
            Divider()
            
            // Tab content
            Group {
                switch selectedTab {
                case .sequences:
                    SequencesTabView(timelineViewModel: timelineViewModel)
                case .mediaBin:
                    MediaBinTabView(projectViewModel: projectViewModel)
                }
            }
            
            Divider()
            
            // Bottom toolbar with + dropdown and glass effect
            HStack(spacing: 8) {
                Menu {
                    Button("Import Video...") {
                        showingImportDialog = true
                    }
                    
                    Divider()
                    
                    Button("New Sequence") {
                        createNewSequence()
                    }
                } label: {
                    Label("Add", systemImage: "plus")
                        .frame(maxWidth: .infinity)
                }
                .menuStyle(.borderlessButton)
                .frame(height: 28)
            }
            .padding(8)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .fileImporter(
            isPresented: $showingImportDialog,
            allowedContentTypes: [.movie, .video, .mpeg4Movie, .quickTimeMovie],
            allowsMultipleSelection: true
        ) { result in
            handleImport(result)
        }
    }
    
    private func createNewSequence() {
        let timeline = Timeline(name: "Sequence \(timelineViewModel.timelines.count + 1)")
        timelineViewModel.timelines.append(timeline)
        timelineViewModel.setActiveTimeline(timeline)
        // Timeline is always visible in Phase 7
    }
    
    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            // Use ProjectViewModel's existing addVideos method
            Task {
                await projectViewModel.addVideos(from: urls)
                
                // Switch to media bin tab to show imported videos
                selectedTab = .mediaBin
            }
            
        case .failure(let error):
            print("Import failed: \(error)")
        }
    }
}

#Preview {
    @Previewable @State var projectVM = ProjectViewModel()
    @Previewable @State var timelineVM = TimelineViewModel()
    
    ProjectSidebarView(
        projectViewModel: projectVM,
        timelineViewModel: timelineVM
    )
    .frame(width: 220, height: 500)
}
