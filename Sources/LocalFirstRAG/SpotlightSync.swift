import CoreSpotlight
import Foundation
import NaturalLanguage
import UniformTypeIdentifiers

/// Abstracts the subset of `CSSearchableIndex` operations `LocalIndex` needs.
///
/// Tests use a recording test double conforming to this protocol to verify
/// the `spotlightVisible` privacy boundary precisely — whether an excluded
/// document's item is ever passed to `indexSearchableItems`, rather than
/// depending on the real system Spotlight index's eventual consistency.
protocol SearchableIndexClient: Sendable {
    func indexSearchableItems(_ items: [CSSearchableItem]) async throws
    func deleteSearchableItems(withIdentifiers identifiers: [String]) async throws
}

extension CSSearchableIndex: SearchableIndexClient {}

/// A plain, `Sendable` snapshot of the document fields `SpotlightSync` needs.
///
/// `IndexedDocument` is a SwiftData `@Model` reference bound to its
/// originating `ModelContext`; it isn't safe to hand across the actor
/// boundary into these `nonisolated` sync functions, so `LocalIndex` snapshots
/// the fields it needs into this value type first.
struct SyncableDocument: Sendable {
    let id: String
    let text: String
    let spotlightVisible: Bool
}

/// Keeps a Core Spotlight index in lockstep with a `LocalIndex`'s SwiftData
/// store: documents with `spotlightVisible == true` become searchable
/// system-wide; documents with `spotlightVisible == false` are embedded and
/// stored for in-app search as normal, but are never handed to
/// `CSSearchableIndex` — the one privacy boundary this package exposes.
enum SpotlightSync {
    /// Groups this package's Spotlight items so they can be bulk-managed
    /// without touching other items the host app may index for other purposes.
    static let domainIdentifier = "com.localfirstrag.index"

    /// Indexes `document` if `spotlightVisible`, or ensures it's removed
    /// from the Spotlight index otherwise. Covers both `add` (new document)
    /// and `update` (content or visibility changed) call sites.
    static func sync(_ document: SyncableDocument, using client: some SearchableIndexClient) async throws {
        if document.spotlightVisible {
            try await client.indexSearchableItems([searchableItem(for: document)])
        } else {
            try await client.deleteSearchableItems(withIdentifiers: [document.id])
        }
    }

    /// Removes a document's item from the Spotlight index unconditionally
    /// (harmless no-op if it was never indexed, e.g. because it was excluded).
    static func remove(id: String, using client: some SearchableIndexClient) async throws {
        try await client.deleteSearchableItems(withIdentifiers: [id])
    }

    static func searchableItem(for document: SyncableDocument) -> CSSearchableItem {
        let attributeSet = CSSearchableItemAttributeSet(contentType: .text)
        attributeSet.title = title(from: document.text)
        attributeSet.contentDescription = String(document.text.prefix(400))
        attributeSet.keywords = keywords(from: document.text)

        return CSSearchableItem(
            uniqueIdentifier: document.id,
            domainIdentifier: domainIdentifier,
            attributeSet: attributeSet
        )
    }

    private static func title(from text: String) -> String {
        let firstLine = text
            .split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? text
        return String(firstLine.prefix(80))
    }

    /// Derives keywords from the document's nouns, so Spotlight results are
    /// genuinely findable by the terms a user is likely to search for.
    private static func keywords(from text: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        let tagger = NLTagger(tagSchemes: [.lexicalClass])
        tagger.string = text
        tagger.enumerateTags(in: text.startIndex..<text.endIndex, unit: .word, scheme: .lexicalClass) { tag, range in
            if tag == .noun {
                let word = text[range].lowercased()
                if seen.insert(word).inserted {
                    result.append(word)
                }
            }
            return result.count < 20
        }
        return result
    }
}
