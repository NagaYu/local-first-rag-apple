import AppIntents
import LocalFirstRAG
import SwiftUI

@main
struct NotesAppApp: App {
    @State private var index: LocalIndex?
    @State private var setupError: Error?

    var body: some Scene {
        WindowGroup {
            Group {
                if let index {
                    ContentView(index: index)
                } else if let setupError {
                    Text("Failed to open index: \(setupError.localizedDescription)")
                } else {
                    ProgressView("Opening index…")
                }
            }
            .task {
                await setUpIndexIfNeeded()
            }
        }
    }

    /// Opens the shared `LocalIndex`, registers it for `SearchLocalIndexIntent`
    /// via `AppDependencyManager` (the mechanism a host app uses to make its
    /// index reachable from Siri/Shortcuts), and seeds a couple of example
    /// notes — including one marked `spotlightVisible: false` — on first launch.
    private func setUpIndexIfNeeded() async {
        guard index == nil else { return }
        do {
            let opened = try LocalIndex(name: "notes-app-example")
            AppDependencyManager.shared.add(dependency: { opened })
            try await seedExampleNotesIfEmpty(in: opened)
            index = opened
        } catch {
            setupError = error
        }
    }

    private func seedExampleNotesIfEmpty(in index: LocalIndex) async throws {
        let existing = try await index.search("note", topK: 1)
        guard existing.isEmpty else { return }

        try await index.add(
            id: "kyoto-trip",
            text: "Notes about the trip to Kyoto: visited Fushimi Inari at sunrise, "
                + "walked through the bamboo grove in Arashiyama, and had matcha near "
                + "the Philosopher's Path. Want to go back in autumn for the leaves.",
            spotlightVisible: true
        )
        try await index.add(
            id: "therapy-journal",
            text: "Private journal entry: talked through the move and the job change "
                + "in this week's session. Feeling less anxious about the transition.",
            spotlightVisible: false
        )
    }
}
