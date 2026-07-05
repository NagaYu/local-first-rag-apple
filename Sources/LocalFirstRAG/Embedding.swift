import Foundation
import NaturalLanguage

/// Errors produced while embedding text with `NLEmbedding`.
public enum EmbeddingError: Error, Sendable, Equatable {
    /// No `NLEmbedding.sentenceEmbedding` model is available for this language on this device.
    case unsupportedLanguage(NLLanguage)
    /// The model could not produce a vector for the given text (e.g. empty or unrecognized input).
    case vectorUnavailable
}

/// Wraps `NLEmbedding.sentenceEmbedding(for:)` — the committed embedding
/// source for this package (see README for why, and why not
/// `NLContextualEmbedding` or Apple Intelligence's `FoundationModels`).
///
/// `NLEmbedding.sentenceEmbedding` models are per-language, so one
/// `TextEmbedder` — and one `LocalIndex` — is scoped to a single primary
/// language. An actor, since `NLEmbedding` isn't documented as safe for
/// concurrent access from multiple threads.
public actor TextEmbedder {
    public let language: NLLanguage
    private let embedding: NLEmbedding

    public init(language: NLLanguage) throws {
        guard let embedding = NLEmbedding.sentenceEmbedding(for: language) else {
            throw EmbeddingError.unsupportedLanguage(language)
        }
        self.language = language
        self.embedding = embedding
    }

    /// Embeds `text` into a vector in this embedder's language-specific vector space.
    public func embed(_ text: String) throws -> [Float] {
        guard let vector = embedding.vector(for: text) else {
            throw EmbeddingError.vectorUnavailable
        }
        return vector.map(Float.init)
    }

    /// Detects the dominant language of `text`, falling back to `fallback` when detection is inconclusive.
    public static func detectLanguage(for text: String, fallback: NLLanguage = .english) -> NLLanguage {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        return recognizer.dominantLanguage ?? fallback
    }
}
