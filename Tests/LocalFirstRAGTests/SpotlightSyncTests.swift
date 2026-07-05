import CoreSpotlight
import XCTest
@testable import LocalFirstRAG

/// Records calls instead of touching the real system Spotlight index, so
/// tests can assert precisely which documents' items ever reach
/// `indexSearchableItems` — the actual privacy boundary this package
/// promises — without depending on the real index's eventual consistency.
///
/// `CSSearchableItem` isn't `Sendable`, so this can't be an actor (that would
/// require sending non-Sendable items across an isolation boundary); a lock
/// guards the mutable state instead.
final class RecordingSearchableIndexClient: SearchableIndexClient, @unchecked Sendable {
    private let lock = NSLock()
    private var _indexedItemIdentifiers: [String] = []
    private var _deletedIdentifiers: [String] = []

    var indexedItemIdentifiers: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _indexedItemIdentifiers
    }

    var deletedIdentifiers: [String] {
        lock.lock()
        defer { lock.unlock() }
        return _deletedIdentifiers
    }

    func indexSearchableItems(_ items: [CSSearchableItem]) async throws {
        appendIndexed(items.map(\.uniqueIdentifier))
    }

    func deleteSearchableItems(withIdentifiers identifiers: [String]) async throws {
        appendDeleted(identifiers)
    }

    // Locking directly inside an `async` function body is disallowed (a
    // suspension point could occur while the lock is held); these plain
    // synchronous helpers keep the critical section outside of any `await`.
    private func appendIndexed(_ ids: [String]) {
        lock.lock()
        _indexedItemIdentifiers.append(contentsOf: ids)
        lock.unlock()
    }

    private func appendDeleted(_ ids: [String]) {
        lock.lock()
        _deletedIdentifiers.append(contentsOf: ids)
        lock.unlock()
    }
}

final class SpotlightSyncTests: XCTestCase {
    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    // MARK: - The privacy boundary itself

    func testSpotlightVisibleFalseNeverReachesSearchableIndex() async throws {
        let client = RecordingSearchableIndexClient()
        let index = try LocalIndex(
            name: "notes",
            language: .english,
            directory: makeTempDirectory(),
            spotlightIndex: client
        )

        try await index.add(id: "hidden", text: "A private journal entry about therapy sessions.", spotlightVisible: false)
        try await index.add(id: "visible", text: "A public note about a trip to Kyoto.", spotlightVisible: true)

        let indexedIDs = client.indexedItemIdentifiers
        XCTAssertFalse(indexedIDs.contains("hidden"), "excluded document must never be passed to indexSearchableItems")
        XCTAssertTrue(indexedIDs.contains("visible"))

        // Still fully searchable in-app regardless of Spotlight visibility.
        let results = try await index.search("private journal therapy", topK: 5)
        XCTAssertTrue(results.contains { $0.id == "hidden" })
    }

    func testFlippingVisibleToHiddenDeletesFromSearchableIndex() async throws {
        let client = RecordingSearchableIndexClient()
        let index = try LocalIndex(
            name: "notes",
            language: .english,
            directory: makeTempDirectory(),
            spotlightIndex: client
        )

        try await index.add(id: "note-1", text: "Some note.", spotlightVisible: true)
        XCTAssertTrue(client.indexedItemIdentifiers.contains("note-1"))

        try await index.update(id: "note-1", spotlightVisible: false)
        XCTAssertTrue(client.deletedIdentifiers.contains("note-1"))
    }

    func testFlippingHiddenToVisibleIndexesForTheFirstTime() async throws {
        let client = RecordingSearchableIndexClient()
        let index = try LocalIndex(
            name: "notes",
            language: .english,
            directory: makeTempDirectory(),
            spotlightIndex: client
        )

        try await index.add(id: "note-1", text: "Some note.", spotlightVisible: false)
        XCTAssertFalse(client.indexedItemIdentifiers.contains("note-1"))

        try await index.update(id: "note-1", spotlightVisible: true)
        XCTAssertTrue(client.indexedItemIdentifiers.contains("note-1"))
    }

    func testRemoveDeletesFromSearchableIndexRegardlessOfVisibility() async throws {
        let client = RecordingSearchableIndexClient()
        let index = try LocalIndex(
            name: "notes",
            language: .english,
            directory: makeTempDirectory(),
            spotlightIndex: client
        )

        try await index.add(id: "note-1", text: "Some note.", spotlightVisible: true)
        try await index.remove(id: "note-1")

        XCTAssertTrue(client.deletedIdentifiers.contains("note-1"))
    }

    // MARK: - Attribute set quality

    func testSearchableItemHasUsefulAttributes() {
        let document = SyncableDocument(
            id: "note-1",
            text: "Kyoto Trip\nVisited temples and gardens in the old capital with friends.",
            spotlightVisible: true
        )

        let item = SpotlightSync.searchableItem(for: document)

        XCTAssertEqual(item.uniqueIdentifier, "note-1")
        XCTAssertEqual(item.attributeSet.title, "Kyoto Trip")
        XCTAssertEqual(item.attributeSet.contentDescription, document.text)
        XCTAssertFalse(item.attributeSet.keywords?.isEmpty ?? true)
        XCTAssertTrue(item.attributeSet.keywords?.contains("trip") ?? false)
    }
}
