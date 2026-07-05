import XCTest
import NaturalLanguage
@testable import LocalFirstRAG

final class EmbeddingTests: XCTestCase {
    func testEmbedProducesANonEmptyVector() async throws {
        let embedder = try TextEmbedder(language: .english)
        let vector = try await embedder.embed("A trip to Kyoto in autumn.")
        XCTAssertGreaterThan(vector.count, 0)
    }

    func testEmbeddingIsDeterministic() async throws {
        let embedder = try TextEmbedder(language: .english)
        let text = "Notes from the Kyoto trip about temples and gardens."
        let first = try await embedder.embed(text)
        let second = try await embedder.embed(text)
        XCTAssertEqual(first, second)
    }

    func testSimilarSentencesAreMoreSimilarThanUnrelatedOnes() async throws {
        let embedder = try TextEmbedder(language: .english)
        let base = try await embedder.embed("What did I write about the trip to Kyoto?")
        let related = try await embedder.embed("Notes about visiting temples in Kyoto last spring.")
        let unrelated = try await embedder.embed("Quarterly financial report for the accounting department.")

        let relatedScore = cosineSimilarity(base, related)
        let unrelatedScore = cosineSimilarity(base, unrelated)

        XCTAssertGreaterThan(relatedScore, unrelatedScore)
    }

    func testDetectLanguageRecognizesEnglish() {
        let language = TextEmbedder.detectLanguage(for: "This note is written in English.")
        XCTAssertEqual(language, .english)
    }

    private func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        let dot = zip(a, b).reduce(Float(0)) { $0 + $1.0 * $1.1 }
        let magnitudeA = sqrt(a.reduce(Float(0)) { $0 + $1 * $1 })
        let magnitudeB = sqrt(b.reduce(Float(0)) { $0 + $1 * $1 })
        guard magnitudeA > 0, magnitudeB > 0 else { return 0 }
        return dot / (magnitudeA * magnitudeB)
    }
}
