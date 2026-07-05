import AppIntents
import Foundation

/// Makes a `LocalIndex` queryable via Siri and the Shortcuts app.
///
/// A host app registers its `LocalIndex` once, at launch, via
/// `AppDependencyManager`:
///
/// ```swift
/// AppDependencyManager.shared.add(dependency: { myIndex })
/// ```
///
/// Results are restricted to documents with `spotlightVisible == true` — the
/// same boundary this package applies to Core Spotlight, so "excluded from
/// system integration" means one privacy boundary a developer reasons about
/// once, not two different ones for Spotlight and Siri/Shortcuts.
public struct SearchLocalIndexIntent: AppIntent {
    public static let title: LocalizedStringResource = "Search My Notes"
    public static let description = IntentDescription(
        "Searches your local semantic index and returns the most relevant notes."
    )

    @Dependency
    var index: LocalIndex

    @Parameter(title: "Search for")
    public var query: String

    public static var parameterSummary: some ParameterSummary {
        Summary("Search notes for \(\.$query)")
    }

    public init() {}

    public init(query: String) {
        self.query = query
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        try await Self.performSearch(query, using: index)
    }

    /// The intent's actual logic, factored out of `perform()` so it's
    /// testable directly: `@Dependency`'s `index` only resolves inside the
    /// real intent-perform flow (Siri/Shortcuts, or `AppIntentsTesting`) and
    /// traps if accessed from a plain unit test.
    static func performSearch(_ query: String, using index: LocalIndex) async throws -> some IntentResult & ReturnsValue<[String]> {
        let results = try await index.search(query, topK: 5, restrictToSpotlightVisible: true)
        return .result(value: results.map(\.text))
    }
}
