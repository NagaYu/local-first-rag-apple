import Accelerate

/// A candidate's rank within a similarity search, referring back to its
/// position in the `candidates` array passed to `SimilarityRanking.topK`.
public struct ScoredChunk: Sendable, Equatable {
    public let index: Int
    public let score: Float
}

/// Accelerate (vDSP)-based cosine similarity ranking over fetched candidate
/// vectors. There is no SwiftData-native vector index, so `LocalIndex`
/// fetches candidate embeddings and ranks them here — appropriate for the
/// personal-scale target of thousands, not millions, of chunks (see README).
public enum SimilarityRanking {
    /// Ranks `candidates` by cosine similarity to `query`, returning the
    /// `topK` highest-scoring candidates in descending order of score.
    ///
    /// `ScoredChunk.index` is the candidate's position in `candidates`, so
    /// callers can map it back to the chunk (and document) it came from.
    public static func topK(query: [Float], candidates: [[Float]], topK: Int) -> [ScoredChunk] {
        guard topK > 0, !candidates.isEmpty else { return [] }

        let scores = candidates.map { cosineSimilarity(query, $0) }
        let rankedIndices = scores.indices.sorted { scores[$0] > scores[$1] }

        return rankedIndices.prefix(topK).map { ScoredChunk(index: $0, score: scores[$0]) }
    }

    /// Cosine similarity between two vectors. Returns `0` for empty vectors,
    /// mismatched dimensions, or zero-magnitude vectors, rather than dividing by zero.
    public static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard !a.isEmpty, a.count == b.count else { return 0 }

        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))

        var sumOfSquaresA: Float = 0
        vDSP_svesq(a, 1, &sumOfSquaresA, vDSP_Length(a.count))
        var sumOfSquaresB: Float = 0
        vDSP_svesq(b, 1, &sumOfSquaresB, vDSP_Length(b.count))

        let magnitude = (sumOfSquaresA * sumOfSquaresB).squareRoot()
        guard magnitude > 0 else { return 0 }

        return dot / magnitude
    }
}
