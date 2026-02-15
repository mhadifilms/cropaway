//
//  SequenceSidebarView.swift
//  Cropaway
//
//  Sidebar displaying list of sequences in the project.
//

import SwiftUI

struct SequenceSidebarView: View {
    @EnvironmentObject var projectVM: ProjectViewModel
    
    var body: some View {
        List(selection: $projectVM.project.selectedSequence) {
            Section("Sequences") {
                ForEach(projectVM.project.sequences) { sequence in
                    SequenceListItemView(sequence: sequence)
                        .tag(sequence)
                }
                .onDelete(perform: deleteSequences)
            }
        }
        .navigationTitle("Sequences")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: createSequence) {
                    Label("New Sequence", systemImage: "plus")
                }
            }
        }
    }
    
    private func createSequence() {
        let count = projectVM.project.sequences.count
        _ = projectVM.createSequence(name: "Sequence \(count + 1)")
    }
    
    private func deleteSequences(at offsets: IndexSet) {
        for index in offsets {
            let sequence = projectVM.project.sequences[index]
            projectVM.removeSequence(sequence)
        }
    }
}

struct SequenceListItemView: View {
    @ObservedObject var sequence: Sequence
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(sequence.name)
                .font(.headline)
            
            HStack(spacing: 8) {
                Label(formatDuration(sequence.duration), systemImage: "clock")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Label("\(sequence.clips.count) clips", systemImage: "film")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let totalSeconds = Int(seconds)
        let minutes = totalSeconds / 60
        let secs = totalSeconds % 60
        return String(format: "%d:%02d", minutes, secs)
    }
}

struct SequenceSidebarView_Previews: PreviewProvider {
    static var previews: some View {
        let projectVM = ProjectViewModel()
        _ = projectVM.createSequence(name: "Main Sequence")
        _ = projectVM.createSequence(name: "B-Roll")
        
        return NavigationSplitView {
            SequenceSidebarView()
                .environmentObject(projectVM)
        } detail: {
            Text("Select a sequence")
        }
    }
}
