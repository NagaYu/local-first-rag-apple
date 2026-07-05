import XCTest
@testable import LocalFirstRAG

final class ChunkingTests: XCTestCase {
    func testEmptyTextProducesNoChunks() {
        XCTAssertEqual(Chunker.chunk(""), [])
        XCTAssertEqual(Chunker.chunk("   \n\t  "), [])
    }

    func testShortTextProducesASingleChunk() {
        let text = "This is a short note about a trip to Kyoto."
        let chunks = Chunker.chunk(text, config: .default)
        XCTAssertEqual(chunks, [text])
    }

    func testLongTextIsSplitIntoMultipleChunksWithinTargetSize() {
        let sentence = "The quick brown fox jumps over the lazy dog in the garden today."
        let text = Array(repeating: sentence, count: 20).joined(separator: " ")
        let config = ChunkingConfig(targetCharacterCount: 200, overlapCharacterCount: 40)

        let chunks = Chunker.chunk(text, config: config)

        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            // A chunk may exceed the target only when a single sentence alone does; here no sentence does.
            XCTAssertLessThanOrEqual(chunk.count, config.targetCharacterCount + sentence.count)
        }
        // Reassembling chunks should still contain every sentence from the source.
        XCTAssertTrue(chunks.joined(separator: " ").contains(sentence))
    }

    func testConsecutiveChunksOverlap() {
        let sentences = (1...10).map { "Sentence number \($0) has some unique filler words in it." }
        let text = sentences.joined(separator: " ")
        let config = ChunkingConfig(targetCharacterCount: 120, overlapCharacterCount: 30)

        let chunks = Chunker.chunk(text, config: config)
        XCTAssertGreaterThan(chunks.count, 1)

        for i in 1..<chunks.count {
            let previousTail = chunks[i - 1].suffix(config.overlapCharacterCount)
            XCTAssertTrue(
                chunks[i].hasPrefix(previousTail) || chunks[i].contains(previousTail.trimmingCharacters(in: .whitespaces)),
                "chunk \(i) should carry over trailing context from chunk \(i - 1)"
            )
        }
    }

    func testSingleSentenceLongerThanTargetIsHardSplit() {
        let longWord = String(repeating: "a", count: 50)
        let sentence = Array(repeating: longWord, count: 20).joined(separator: " ") + "."
        let config = ChunkingConfig(targetCharacterCount: 100, overlapCharacterCount: 10)

        let chunks = Chunker.chunk(sentence, config: config)

        XCTAssertGreaterThan(chunks.count, 1)
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.count, config.targetCharacterCount)
        }
    }

    func testInvalidConfigsPreconditionsAreDocumented() {
        // targetCharacterCount must be positive and overlap must be smaller than target;
        // covered by `precondition` in ChunkingConfig.init, exercised via the default config's
        // documented values rather than triggering a trap in a unit test.
        XCTAssertEqual(ChunkingConfig.default.targetCharacterCount, 500)
        XCTAssertEqual(ChunkingConfig.default.overlapCharacterCount, 80)
    }
}
