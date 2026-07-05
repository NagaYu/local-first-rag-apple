import LocalFirstRAG
import SwiftUI

/// Demonstrates the in-app search surface. The same `LocalIndex` backing
/// this view is also registered for Siri/Shortcuts (`NotesAppApp`) and syncs
/// visible documents to system Spotlight automatically (`LocalIndex.add`).
struct ContentView: View {
    let index: LocalIndex

    @State private var query = ""
    @State private var results: [LocalIndex.SearchResult] = []
    @State private var isAddingNote = false
    @State private var searchError: Error?

    var body: some View {
        NavigationStack {
            List {
                Section("Search across in-app, Spotlight, and Siri") {
                    if let searchError {
                        Text("Search failed: \(searchError.localizedDescription)")
                            .foregroundStyle(.red)
                    }
                    ForEach(results, id: \.id) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.id).font(.headline)
                            Text(result.text).font(.subheadline).lineLimit(3)
                            Text("score: \(result.score, specifier: "%.3f")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .searchable(text: $query, prompt: "What did I write about…?")
            .onChange(of: query) { _, newValue in
                Task { await runSearch(newValue) }
            }
            .navigationTitle("Notes")
            .toolbar {
                ToolbarItem {
                    Button("Add Note", systemImage: "plus") { isAddingNote = true }
                }
            }
            .sheet(isPresented: $isAddingNote) {
                AddNoteView(index: index) {
                    Task { await runSearch(query) }
                }
            }
        }
    }

    private func runSearch(_ text: String) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            results = []
            return
        }
        do {
            results = try await index.search(text, topK: 5)
            searchError = nil
        } catch {
            searchError = error
        }
    }
}
