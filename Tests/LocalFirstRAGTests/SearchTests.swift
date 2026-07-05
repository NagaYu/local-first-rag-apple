import XCTest
@testable import LocalFirstRAG

final class SearchTests: XCTestCase {
    func testCosineSimilarityOfIdenticalVectorsIsOne() {
        let vector: [Float] = [1, 2, 3]
        XCTAssertEqual(SimilarityRanking.cosineSimilarity(vector, vector), 1, accuracy: 0.0001)
    }

    func testCosineSimilarityOfOrthogonalVectorsIsZero() {
        let a: [Float] = [1, 0, 0]
        let b: [Float] = [0, 1, 0]
        XCTAssertEqual(SimilarityRanking.cosineSimilarity(a, b), 0, accuracy: 0.0001)
    }

    func testCosineSimilarityOfOppositeVectorsIsNegativeOne() {
        let a: [Float] = [1, 0, 0]
        let b: [Float] = [-1, 0, 0]
        XCTAssertEqual(SimilarityRanking.cosineSimilarity(a, b), -1, accuracy: 0.0001)
    }

    func testCosineSimilarityHandlesMismatchedDimensionsAndEmptyVectorsSafely() {
        XCTAssertEqual(SimilarityRanking.cosineSimilarity([1, 0], [1, 0, 0]), 0)
        XCTAssertEqual(SimilarityRanking.cosineSimilarity([], []), 0)
        XCTAssertEqual(SimilarityRanking.cosineSimilarity([0, 0, 0], [1, 2, 3]), 0)
    }

    func testTopKReturnsCorrectlyRankedOrderForFixtureVectors() {
        let query: [Float] = [1, 0, 0]
        // Known expected ordering by descending cosine similarity to `query`:
        // exact match > near match > orthogonal > opposite.
        let exactMatch: [Float] = [1, 0, 0]
        let nearMatch: [Float] = [0.9, 0.1, 0]
        let orthogonal: [Float] = [0, 1, 0]
        let opposite: [Float] = [-1, 0, 0]
        let candidates = [orthogonal, opposite, nearMatch, exactMatch] // deliberately shuffled

        let results = SimilarityRanking.topK(query: query, candidates: candidates, topK: 3)

        XCTAssertEqual(results.map(\.index), [3, 2, 0]) // exactMatch, nearMatch, orthogonal
        XCTAssertEqual(results[0].score, 1, accuracy: 0.0001)
        XCTAssertGreaterThan(results[0].score, results[1].score)
        XCTAssertGreaterThan(results[1].score, results[2].score)
    }

    func testTopKRespectsRequestedLimit() {
        let query: [Float] = [1, 0]
        let candidates: [[Float]] = [[1, 0], [0.8, 0.2], [0.5, 0.5], [0, 1]]

        XCTAssertEqual(SimilarityRanking.topK(query: query, candidates: candidates, topK: 2).count, 2)
        XCTAssertEqual(SimilarityRanking.topK(query: query, candidates: candidates, topK: 0).count, 0)
        XCTAssertEqual(SimilarityRanking.topK(query: query, candidates: [], topK: 5).count, 0)
    }
}
