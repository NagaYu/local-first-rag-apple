import XCTest
import NaturalLanguage
@testable import LocalFirstRAG

final class LocalIndexTests: XCTestCase {
    private func makeTempDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    func testAddThenSearchFindsDocument() async throws {
        let index = try LocalIndex(name: "notes", language: .english, directory: makeTempDirectory())
        try await index.add(id: "note-1", text: "Notes about the trip to Kyoto, temples and gardens.")

        let results = try await index.search("what did I write about the trip to Kyoto?", topK: 5)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, "note-1")
    }

    func testAddDuplicateIdThrows() async throws {
        let index = try LocalIndex(name: "notes", language: .english, directory: makeTempDirectory())
        try await index.add(id: "note-1", text: "First version of the note.")

        do {
            try await index.add(id: "note-1", text: "Second version of the note.")
            XCTFail("expected documentAlreadyExists")
        } catch LocalIndex.LocalIndexError.documentAlreadyExists(let id) {
            XCTAssertEqual(id, "note-1")
        }
    }

    func testUpdateNonExistentThrows() async throws {
        let index = try LocalIndex(name: "notes", language: .english, directory: makeTempDirectory())

        do {
            try await index.update(id: "missing", text: "irrelevant")
            XCTFail("expected documentNotFound")
        } catch LocalIndex.LocalIndexError.documentNotFound(let id) {
            XCTAssertEqual(id, "missing")
        }
    }

    func testUpdateReplacesContentAndChunks() async throws {
        let index = try LocalIndex(name: "notes", language: .english, directory: makeTempDirectory())
        try await index.add(id: "note-1", text: "A recipe for tomato soup with basil.")
        try await index.update(id: "note-1", text: "Quarterly budget planning for the marketing team.")

        let results = try await index.search("quarterly marketing budget", topK: 5)

        XCTAssertEqual(results.first?.id, "note-1")
        XCTAssertTrue(results.first?.text.contains("budget") ?? false)
    }

    func testRemoveDeletesDocument() async throws {
        let index = try LocalIndex(name: "notes", language: .english, directory: makeTempDirectory())
        try await index.add(id: "note-1", text: "Notes about a trip to Kyoto.")
        try await index.remove(id: "note-1")

        let results = try await index.search("trip to Kyoto", topK: 5)
        XCTAssertTrue(results.isEmpty)

        do {
            try await index.remove(id: "note-1")
            XCTFail("expected documentNotFound")
        } catch LocalIndex.LocalIndexError.documentNotFound(let id) {
            XCTAssertEqual(id, "note-1")
        }
    }

    func testSearchRanksMostRelevantDocumentFirst() async throws {
        let index = try LocalIndex(name: "notes", language: .english, directory: makeTempDirectory())
        try await index.add(id: "kyoto", text: "Notes about visiting temples and gardens in Kyoto last spring.")
        try await index.add(id: "budget", text: "Quarterly financial report for the accounting department.")
        try await index.add(id: "recipe", text: "A simple recipe for tomato soup with fresh basil.")

        let results = try await index.search("what did I write about the trip to Kyoto?", topK: 3)

        XCTAssertEqual(results.first?.id, "kyoto")
    }

    func testSearchDeduplicatesMultipleMatchingChunksToOneResultPerDocument() async throws {
        let index = try LocalIndex(name: "notes", language: .english, directory: makeTempDirectory())
        let longText = Array(
            repeating: "Kyoto temples and gardens were beautiful in the spring sunlight.",
            count: 10
        ).joined(separator: " ")
        try await index.add(id: "kyoto", text: longText)

        let results = try await index.search("Kyoto temples", topK: 5)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.id, "kyoto")
    }

    func testSearchOnEmptyIndexReturnsEmptyWithoutThrowing() async throws {
        let index = try LocalIndex(name: "notes", directory: makeTempDirectory())
        let results = try await index.search("anything", topK: 5)
        XCTAssertTrue(results.isEmpty)
    }

    func testSearchTopKZeroReturnsEmpty() async throws {
        let index = try LocalIndex(name: "notes", language: .english, directory: makeTempDirectory())
        try await index.add(id: "note-1", text: "Some content.")
        let results = try await index.search("content", topK: 0)
        XCTAssertTrue(results.isEmpty)
    }

    func testReopeningIndexPersistsPreviouslyAddedDocuments() async throws {
        let directory = makeTempDirectory()

        do {
            let index = try LocalIndex(name: "persistent-notes", language: .english, directory: directory)
            try await index.add(id: "note-1", text: "Notes about a trip to Kyoto, temples and gardens.")
        }

        let reopened = try LocalIndex(name: "persistent-notes", directory: directory)
        let results = try await reopened.search("trip to Kyoto", topK: 5)

        XCTAssertEqual(results.first?.id, "note-1")
    }

    func testExplicitLanguageMismatchWithStoredLanguageThrows() async throws {
        let directory = makeTempDirectory()

        do {
            let index = try LocalIndex(name: "notes", language: .english, directory: directory)
            try await index.add(id: "note-1", text: "An English note.")
        }

        XCTAssertThrowsError(try LocalIndex(name: "notes", language: .japanese, directory: directory)) { error in
            guard case LocalIndex.LocalIndexError.languageMismatch(let stored, let requested) = error else {
                XCTFail("expected languageMismatch, got \(error)")
                return
            }
            XCTAssertEqual(stored, .english)
            XCTAssertEqual(requested, .japanese)
        }
    }
}
