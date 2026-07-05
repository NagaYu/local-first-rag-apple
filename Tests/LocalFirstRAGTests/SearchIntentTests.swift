import AppIntents
import XCTest
@testable import LocalFirstRAG

/// Exercises `SearchLocalIndexIntent`'s actual search logic directly.
///
/// `@Dependency`'s `index` only resolves inside the real intent-perform flow
/// (Siri/Shortcuts, or the `AppIntentsTesting` framework) and traps if
/// accessed from a plain unit test — confirmed empirically: calling
/// `intent.perform()` directly here crashes with "AppDependency ... was not
/// initialized prior to access." So these tests call `performSearch`
/// directly, which is the intent's real logic minus dependency resolution.
/// Full system-level verification via `AppIntentsTesting`, including the
/// real `@Dependency` path, lives in `Examples/NotesApp` (see CONTRIBUTING.md).
final class SearchIntentTests: XCTestCase {
    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    func testPerformSearchReturnsRelevantResults() async throws {
        let index = try LocalIndex(name: "notes", language: .english, directory: makeTempDirectory())
        try await index.add(id: "kyoto", text: "Notes about visiting temples and gardens in Kyoto last spring.")
        try await index.add(id: "budget", text: "Quarterly financial report for the accounting department.")

        let result = try await SearchLocalIndexIntent.performSearch(
            "what did I write about the trip to Kyoto?",
            using: index
        )

        let texts = try XCTUnwrap(result.value)
        XCTAssertTrue(texts.contains { $0.contains("Kyoto") })
    }

    func testPerformSearchExcludesDocumentsMarkedSpotlightVisibleFalse() async throws {
        let index = try LocalIndex(name: "notes", language: .english, directory: makeTempDirectory())
        try await index.add(id: "hidden", text: "A private journal entry about a difficult week.", spotlightVisible: false)
        try await index.add(id: "visible", text: "A public note about a difficult hiking trail.", spotlightVisible: true)

        let result = try await SearchLocalIndexIntent.performSearch("difficult", using: index)

        let texts = try XCTUnwrap(result.value)
        XCTAssertFalse(texts.contains { $0.contains("journal") }, "Siri/Shortcuts must not surface spotlightVisible: false documents")
        XCTAssertTrue(texts.contains { $0.contains("hiking") })

        // Confirm the excluded document is still fully searchable in-app.
        let inAppResults = try await index.search("difficult journal", topK: 5)
        XCTAssertTrue(inAppResults.contains { $0.id == "hidden" })
    }

    func testIntentCanBeConstructedWithAQueryDirectly() {
        let intent = SearchLocalIndexIntent(query: "trip to Kyoto")
        XCTAssertEqual(intent.query, "trip to Kyoto")
    }
}
