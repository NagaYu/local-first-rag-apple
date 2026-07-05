import Foundation
import SwiftData

/// A single document added to a `LocalIndex`.
///
/// `spotlightVisible` is the one privacy boundary this package exposes: when
/// `false`, the document is embedded and stored for in-app search as normal,
/// but is never handed to Core Spotlight and is excluded from Siri/Shortcuts
/// results surfaced through `SearchLocalIndexIntent`.
@Model
final class IndexedDocument {
    @Attribute(.unique) var id: String
    var text: String
    var spotlightVisible: Bool
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \Chunk.document)
    var chunks: [Chunk] = []

    init(
        id: String,
        text: String,
        spotlightVisible: Bool,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.text = text
        self.spotlightVisible = spotlightVisible
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// A chunk of a document's text, with its embedding vector.
///
/// Chunks, not documents, are the unit of search: `LocalIndex.search` ranks
/// chunks by cosine similarity and surfaces the parent document.
@Model
final class Chunk {
    @Attribute(.unique) var id: String
    var text: String
    var embedding: [Float]
    var chunkIndex: Int
    var document: IndexedDocument?

    init(
        id: String = UUID().uuidString,
        text: String,
        embedding: [Float],
        chunkIndex: Int,
        document: IndexedDocument? = nil
    ) {
        self.id = id
        self.text = text
        self.embedding = embedding
        self.chunkIndex = chunkIndex
        self.document = document
    }
}

/// Index-wide metadata — currently just the resolved `NLLanguage` for the
/// `NLEmbedding.sentenceEmbedding` model this index's chunks were embedded
/// with, so a reopened index keeps using the same (per-language) vector
/// space instead of silently drifting to a different one.
@Model
final class IndexMetadata {
    @Attribute(.unique) var key: String
    var languageRawValue: String

    init(languageRawValue: String) {
        self.key = "language"
        self.languageRawValue = languageRawValue
    }
}
