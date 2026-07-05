import Foundation
import NaturalLanguage

/// Configuration for splitting a document's text into embeddable chunks.
///
/// Defaults target roughly paragraph-sized chunks (~500 characters) with a
/// small overlap so a sentence that begins a semantic idea near a chunk
/// boundary still has some surrounding context in the next chunk. Both are
/// overridable per `LocalIndex` instance.
public struct ChunkingConfig: Sendable, Equatable {
    /// Roughly how many characters each chunk should target. Chunks are
    /// built from whole sentences, so the actual size varies with sentence
    /// boundaries and can exceed this for a single long sentence.
    public var targetCharacterCount: Int

    /// How many trailing characters of a finished chunk are carried over as
    /// the start of the next chunk, for continuity across the boundary.
    public var overlapCharacterCount: Int

    public static let `default` = ChunkingConfig(targetCharacterCount: 500, overlapCharacterCount: 80)

    public init(targetCharacterCount: Int = 500, overlapCharacterCount: Int = 80) {
        precondition(targetCharacterCount > 0, "targetCharacterCount must be positive")
        precondition(
            overlapCharacterCount >= 0 && overlapCharacterCount < targetCharacterCount,
            "overlapCharacterCount must be non-negative and smaller than targetCharacterCount"
        )
        self.targetCharacterCount = targetCharacterCount
        self.overlapCharacterCount = overlapCharacterCount
    }
}

/// Splits document text into sentence-aware chunks suitable for embedding.
public enum Chunker {
    /// Splits `text` into chunks according to `config`.
    ///
    /// Sentences are never split across chunks unless a single sentence
    /// alone exceeds `targetCharacterCount`, in which case it is hard-split
    /// by character count so no chunk grows unbounded.
    public static func chunk(_ text: String, config: ChunkingConfig = .default) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let sentences = sentenceRanges(in: trimmed).map { String(trimmed[$0]) }
        guard !sentences.isEmpty else { return [trimmed] }

        var chunks: [String] = []
        var current = ""

        func flushCurrent() {
            let piece = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty {
                chunks.append(piece)
            }
            current = ""
        }

        for sentence in sentences {
            if sentence.count > config.targetCharacterCount {
                flushCurrent()
                chunks.append(contentsOf: hardSplit(sentence, config: config))
                continue
            }

            if !current.isEmpty && current.count + sentence.count > config.targetCharacterCount {
                flushCurrent()
                let overlap = trailingOverlap(of: chunks.last, config: config)
                current = overlap
            }

            current += (current.isEmpty || current.hasSuffix(" ") ? "" : " ") + sentence
        }
        flushCurrent()

        return chunks
    }

    private static func sentenceRanges(in text: String) -> [Range<String.Index>] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var ranges: [Range<String.Index>] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            ranges.append(range)
            return true
        }
        return ranges
    }

    private static func trailingOverlap(of chunk: String?, config: ChunkingConfig) -> String {
        guard let chunk, config.overlapCharacterCount > 0, chunk.count > config.overlapCharacterCount else {
            return ""
        }
        let startIndex = chunk.index(chunk.endIndex, offsetBy: -config.overlapCharacterCount)
        return String(chunk[startIndex...]) + " "
    }

    private static func hardSplit(_ text: String, config: ChunkingConfig) -> [String] {
        var pieces: [String] = []
        var remainder = Substring(text)
        while remainder.count > config.targetCharacterCount {
            let splitIndex = remainder.index(remainder.startIndex, offsetBy: config.targetCharacterCount)
            pieces.append(String(remainder[remainder.startIndex..<splitIndex]))
            remainder = remainder[splitIndex...]
        }
        if !remainder.isEmpty {
            pieces.append(String(remainder))
        }
        return pieces
    }
}
