import AppIntents
import LocalFirstRAG

/// Registers `SearchLocalIndexIntent` with built-in Siri phrases the moment
/// this app is installed — this (app-specific phrasing, app name) is why
/// `AppShortcutsProvider` conformance lives in the host app, not the package.
struct NotesAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SearchLocalIndexIntent(),
            phrases: [
                "Search my notes in \(.applicationName)",
                "Find notes about \(\.$query) in \(.applicationName)"
            ],
            shortTitle: "Search Notes",
            systemImageName: "magnifyingglass"
        )
    }
}
