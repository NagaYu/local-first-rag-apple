import CoreSpotlight
import Foundation
import NaturalLanguage
import SwiftData

/// The public API for a local semantic search index.
///
/// One `LocalIndex` orchestrates chunking, embedding, and SwiftData
/// persistence for a single named store. From `add(id:text:spotlightVisible:)`
/// alone, the index also keeps Core Spotlight and the bundled Siri/Shortcuts
/// `AppIntent` in lockstep — see `SpotlightSync` and `SearchIntent`.
///
/// `LocalIndex` is scoped to a single primary language, since
/// `NLEmbedding.sentenceEmbedding` models are per-language and their vector
/// spaces aren't comparable across languages. The language is resolved once
/// — either passed explicitly at `init`, or auto-detected from the first
/// document added to a brand-new index — and persisted so a reopened index
/// keeps using the same vector space.
public actor LocalIndex {
    /// A single ranked search result.
    public struct SearchResult: Sendable, Equatable {
        public let id: String
        public let text: String
        public let score: Float
    }

    public enum LocalIndexError: Error, Sendable, Equatable {
        /// `add` was called with an `id` that's already present. Call `update` instead.
        case documentAlreadyExists(id: String)
        /// `update` or `remove` was called with an `id` that isn't present.
        case documentNotFound(id: String)
        /// An explicit `language` was passed to `init` that conflicts with the
        /// language this named index was already created with.
        case languageMismatch(stored: NLLanguage, requested: NLLanguage)
    }

    private let modelContainer: ModelContainer
    private let modelContext: ModelContext
    private let chunkingConfig: ChunkingConfig
    private let explicitLanguage: NLLanguage?
    private let spotlightIndex: any SearchableIndexClient
    private var embedder: TextEmbedder?

    /// Creates or opens a named local index.
    ///
    /// - Parameters:
    ///   - name: Identifies the on-disk store. Reopening with the same name
    ///     (and `directory`, if customized) loads the same documents.
    ///   - language: The primary language to embed with. Defaults to `nil`,
    ///     which auto-detects from the first document added to a brand-new
    ///     index, or reuses the language a previously-created index with
    ///     this name already resolved.
    ///   - chunkingConfig: Overrides the default chunking target size/overlap.
    ///   - directory: Overrides where the store is written. Defaults to an
    ///     app-appropriate Application Support directory; primarily useful
    ///     for tests that need an isolated, disposable location.
    public init(
        name: String,
        language: NLLanguage? = nil,
        chunkingConfig: ChunkingConfig = .default,
        directory: URL? = nil
    ) throws {
        try self.init(
            name: name,
            language: language,
            chunkingConfig: chunkingConfig,
            directory: directory,
            spotlightIndex: CSSearchableIndex.default()
        )
    }

    /// Same as the public initializer, additionally allowing a test double in
    /// place of the real Spotlight index, so tests can verify precisely which
    /// documents' items are (and aren't) ever passed to `CSSearchableIndex`.
    init(
        name: String,
        language: NLLanguage? = nil,
        chunkingConfig: ChunkingConfig = .default,
        directory: URL? = nil,
        spotlightIndex: any SearchableIndexClient
    ) throws {
        let schema = Schema([IndexedDocument.self, Chunk.self, IndexMetadata.self])
        let storeURL = try Self.storeURL(name: name, directory: directory)
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let context = ModelContext(container)

        self.modelContainer = container
        self.modelContext = context
        self.chunkingConfig = chunkingConfig
        self.explicitLanguage = language
        self.spotlightIndex = spotlightIndex

        if let language {
            if let stored = try Self.storedLanguage(in: context), stored != language {
                throw LocalIndexError.languageMismatch(stored: stored, requested: language)
            }
            if try Self.storedLanguage(in: context) == nil {
                try Self.storeLanguage(language, in: context)
            }
            self.embedder = try TextEmbedder(language: language)
        } else if let stored = try Self.storedLanguage(in: context) {
            self.embedder = try TextEmbedder(language: stored)
        } else {
            self.embedder = nil
        }
    }

    /// Chunks, embeds, and persists `text` under `id`.
    ///
    /// - Parameter spotlightVisible: When `false`, this document is embedded
    ///   and stored for in-app search as normal, but is never handed to Core
    ///   Spotlight and is excluded from Siri/Shortcuts results — the one
    ///   privacy boundary this package exposes.
    /// - Throws: `LocalIndexError.documentAlreadyExists` if `id` is already indexed.
    public func add(id: String, text: String, spotlightVisible: Bool = true) async throws {
        if try fetchDocument(id: id) != nil {
            throw LocalIndexError.documentAlreadyExists(id: id)
        }

        let embedder = try resolveEmbedder(seedText: text)
        let document = IndexedDocument(id: id, text: text, spotlightVisible: spotlightVisible)
        modelContext.insert(document)
        try await insertChunks(for: text, into: document, using: embedder)
        try modelContext.save()
        let syncable = SyncableDocument(id: document.id, text: document.text, spotlightVisible: document.spotlightVisible)
        try await SpotlightSync.sync(syncable, using: spotlightIndex)
    }

    /// Updates an existing document's text and/or `spotlightVisible` state.
    ///
    /// Passing `text` re-chunks and re-embeds the document, replacing its
    /// prior chunks entirely.
    /// - Throws: `LocalIndexError.documentNotFound` if `id` isn't indexed.
    public func update(id: String, text: String? = nil, spotlightVisible: Bool? = nil) async throws {
        guard let document = try fetchDocument(id: id) else {
            throw LocalIndexError.documentNotFound(id: id)
        }

        if let text {
            for chunk in document.chunks {
                modelContext.delete(chunk)
            }
            document.text = text
            let embedder = try resolveEmbedder(seedText: text)
            try await insertChunks(for: text, into: document, using: embedder)
        }

        if let spotlightVisible {
            document.spotlightVisible = spotlightVisible
        }

        document.updatedAt = Date()
        try modelContext.save()
        let syncable = SyncableDocument(id: document.id, text: document.text, spotlightVisible: document.spotlightVisible)
        try await SpotlightSync.sync(syncable, using: spotlightIndex)
    }

    /// Removes a document and its chunks entirely.
    /// - Throws: `LocalIndexError.documentNotFound` if `id` isn't indexed.
    public func remove(id: String) async throws {
        guard let document = try fetchDocument(id: id) else {
            throw LocalIndexError.documentNotFound(id: id)
        }
        modelContext.delete(document)
        try modelContext.save()
        try await SpotlightSync.remove(id: id, using: spotlightIndex)
    }

    /// Ranks indexed documents by semantic similarity to `query`.
    ///
    /// Results are deduplicated by document: when multiple chunks from the
    /// same document rank highly, only its best-scoring chunk is returned,
    /// so callers get up to `topK` distinct documents rather than `topK` chunks.
    public func search(_ query: String, topK: Int = 5) async throws -> [SearchResult] {
        try await search(query, topK: topK, restrictToSpotlightVisible: false)
    }

    /// Same as `search(_:topK:)`, additionally restricted to documents with
    /// `spotlightVisible == true` when `restrictToSpotlightVisible` is `true`.
    /// Used internally by `SpotlightSync`'s query path and `SearchLocalIndexIntent`
    /// so both system-facing surfaces share one privacy boundary.
    func search(_ query: String, topK: Int, restrictToSpotlightVisible: Bool) async throws -> [SearchResult] {
        guard topK > 0, let embedder else { return [] }

        let allChunks = try modelContext.fetch(FetchDescriptor<Chunk>())
        let candidates = restrictToSpotlightVisible
            ? allChunks.filter { $0.document?.spotlightVisible == true }
            : allChunks
        guard !candidates.isEmpty else { return [] }

        let queryVector = try await embedder.embed(query)
        let embeddings = candidates.map(\.embedding)
        // Rank every candidate (not just `topK`) so de-duplication by document
        // below can still surface `topK` *distinct* documents.
        let ranked = SimilarityRanking.topK(query: queryVector, candidates: embeddings, topK: candidates.count)

        var seenDocumentIDs = Set<String>()
        var results: [SearchResult] = []
        for scored in ranked {
            let chunk = candidates[scored.index]
            guard let document = chunk.document, !seenDocumentIDs.contains(document.id) else { continue }
            seenDocumentIDs.insert(document.id)
            results.append(SearchResult(id: document.id, text: chunk.text, score: scored.score))
            if results.count == topK { break }
        }
        return results
    }

    // MARK: - Private helpers

    private func insertChunks(for text: String, into document: IndexedDocument, using embedder: TextEmbedder) async throws {
        let pieces = Chunker.chunk(text, config: chunkingConfig)
        for (index, piece) in pieces.enumerated() {
            let vector = try await embedder.embed(piece)
            let chunk = Chunk(text: piece, embedding: vector, chunkIndex: index, document: document)
            modelContext.insert(chunk)
        }
    }

    private func resolveEmbedder(seedText: String) throws -> TextEmbedder {
        if let embedder { return embedder }
        let language = explicitLanguage ?? TextEmbedder.detectLanguage(for: seedText)
        let newEmbedder = try TextEmbedder(language: language)
        if try Self.storedLanguage(in: modelContext) == nil {
            try Self.storeLanguage(language, in: modelContext)
        }
        self.embedder = newEmbedder
        return newEmbedder
    }

    private func fetchDocument(id: String) throws -> IndexedDocument? {
        var descriptor = FetchDescriptor<IndexedDocument>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    private static func storedLanguage(in context: ModelContext) throws -> NLLanguage? {
        var descriptor = FetchDescriptor<IndexMetadata>(predicate: #Predicate { $0.key == "language" })
        descriptor.fetchLimit = 1
        guard let metadata = try context.fetch(descriptor).first else { return nil }
        return NLLanguage(metadata.languageRawValue)
    }

    private static func storeLanguage(_ language: NLLanguage, in context: ModelContext) throws {
        context.insert(IndexMetadata(languageRawValue: language.rawValue))
        try context.save()
    }

    private static func storeURL(name: String, directory: URL?) throws -> URL {
        let baseDirectory: URL
        if let directory {
            baseDirectory = directory
        } else {
            baseDirectory = try FileManager.default
                .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("LocalFirstRAG", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        return baseDirectory.appendingPathComponent("\(name).store")
    }
}
