import XCTest

/// Tests for the pure chunking logic (`TranscriptionChunker`) and transcript
/// reassembly (`TranscriptStitcher`). Both are free of any whisper.cpp runtime
/// dependency and are compiled directly into the test target.
final class TranscriptionChunkerTests: XCTestCase {

    private let sampleRate = 16_000

    /// A small, fast config so tests can use modest sample counts.
    /// maxChunkSamples = 1000, split window = 400, split frame = 100.
    private func config(
        maxChunk: Int = 1000,
        window: Int = 400,
        frame: Int = 100
    ) -> ChunkConfig {
        ChunkConfig(
            sampleRate: sampleRate,
            maxChunkSamples: maxChunk,
            forcedSplitWindowSamples: window,
            forcedSplitFrameSamples: frame
        )
    }

    /// A buffer of constant amplitude `value` of the given length.
    private func buffer(_ length: Int, value: Float = 0.5) -> [Float] {
        Array(repeating: value, count: length)
    }

    // MARK: - Degenerate inputs

    func testNoSegmentsYieldsNoChunks() {
        let plan = TranscriptionChunker.chunk(
            buffer: buffer(1000),
            segments: [],
            config: config()
        )
        XCTAssertTrue(plan.chunks.isEmpty)
        XCTAssertTrue(plan.forcedSplitIndices.isEmpty)
    }

    func testEmptyBufferYieldsNoChunks() {
        let plan = TranscriptionChunker.chunk(
            buffer: [],
            segments: [SpeechSegment(start: 0, end: 100)],
            config: config()
        )
        XCTAssertTrue(plan.chunks.isEmpty)
    }

    // MARK: - Single chunk (short recording fast path)

    func testSingleShortSegmentYieldsOneChunk() {
        let buf = buffer(500)
        let plan = TranscriptionChunker.chunk(
            buffer: buf,
            segments: [SpeechSegment(start: 0, end: 500)],
            config: config()
        )
        XCTAssertEqual(plan.chunks.count, 1)
        XCTAssertEqual(plan.chunks[0].samples.count, 500)
        XCTAssertEqual(plan.chunks[0].startSample, 0)
        XCTAssertEqual(plan.chunks[0].endSample, 500)
        XCTAssertTrue(plan.forcedSplitIndices.isEmpty)
    }

    func testManyShortSegmentsFittingInOneChunk() {
        let buf = buffer(1000)
        let segments = [
            SpeechSegment(start: 0, end: 200),
            SpeechSegment(start: 300, end: 500),
            SpeechSegment(start: 600, end: 800),
        ]
        let plan = TranscriptionChunker.chunk(buffer: buf, segments: segments, config: config())
        XCTAssertEqual(plan.chunks.count, 1)
        // Inter-segment silence is dropped: 200 + 200 + 200 == 600 samples.
        XCTAssertEqual(plan.chunks[0].samples.count, 600)
        XCTAssertEqual(plan.chunks[0].startSample, 0)
        XCTAssertEqual(plan.chunks[0].endSample, 800)
    }

    // MARK: - Multiple chunks with pause boundaries

    func testSegmentsNeedingTwoChunksSplitAtPause() {
        let buf = buffer(2000)
        // Three 400-sample segments. maxChunk 1000 → first two (800) fit, the
        // third would push to 1200 so it starts a second chunk.
        let segments = [
            SpeechSegment(start: 0, end: 400),
            SpeechSegment(start: 500, end: 900),
            SpeechSegment(start: 1000, end: 1400),
        ]
        let plan = TranscriptionChunker.chunk(buffer: buf, segments: segments, config: config())
        XCTAssertEqual(plan.chunks.count, 2)
        XCTAssertEqual(plan.chunks[0].samples.count, 800)
        XCTAssertEqual(plan.chunks[0].startSample, 0)
        XCTAssertEqual(plan.chunks[0].endSample, 900)
        XCTAssertEqual(plan.chunks[1].samples.count, 400)
        XCTAssertEqual(plan.chunks[1].startSample, 1000)
        XCTAssertEqual(plan.chunks[1].endSample, 1400)
        XCTAssertTrue(plan.forcedSplitIndices.isEmpty)
    }

    func testNoChunkExceedsMaxDuration() {
        let buf = buffer(5000)
        let segments = (0..<10).map { i in
            SpeechSegment(start: i * 500, end: i * 500 + 300)
        }
        let plan = TranscriptionChunker.chunk(buffer: buf, segments: segments, config: config())
        for chunk in plan.chunks {
            XCTAssertLessThanOrEqual(chunk.samples.count, 1000)
        }
    }

    // MARK: - Forced split of an over-long segment

    func testGiantSegmentForcesSplitAtLowestEnergyFrame() {
        // One 1500-sample segment, maxChunk 1000. The cut window is
        // [600, 1000); place a silent (zero-energy) frame at [700, 800) so the
        // split lands there.
        var buf = buffer(1500, value: 0.5)
        for i in 700..<800 { buf[i] = 0.0 }

        let plan = TranscriptionChunker.chunk(
            buffer: buf,
            segments: [SpeechSegment(start: 0, end: 1500)],
            config: config()
        )

        XCTAssertEqual(plan.forcedSplitIndices.count, 1)
        XCTAssertEqual(plan.forcedSplitIndices[0], 700)
        XCTAssertEqual(plan.chunks.count, 2)
        // First chunk ends at the split, second carries the remainder.
        XCTAssertEqual(plan.chunks[0].endSample, 700)
        XCTAssertEqual(plan.chunks[1].startSample, 700)
        XCTAssertEqual(plan.chunks[1].endSample, 1500)
        for chunk in plan.chunks {
            XCTAssertLessThanOrEqual(chunk.samples.count, 1000)
        }
    }

    func testForcedSplitMakesProgressWhenNoSilence() {
        // A uniformly loud over-long segment still splits into bounded pieces.
        let buf = buffer(2500, value: 0.7)
        let plan = TranscriptionChunker.chunk(
            buffer: buf,
            segments: [SpeechSegment(start: 0, end: 2500)],
            config: config()
        )
        XCTAssertFalse(plan.chunks.isEmpty)
        for chunk in plan.chunks {
            XCTAssertLessThanOrEqual(chunk.samples.count, 1000)
            XCTAssertGreaterThan(chunk.samples.count, 0)
        }
        // Reassembled chunk lengths cover the whole segment.
        let total = plan.chunks.reduce(0) { $0 + $1.samples.count }
        XCTAssertEqual(total, 2500)
    }

    // MARK: - Segment bounds clamping

    func testSegmentsBeyondBufferAreClamped() {
        let buf = buffer(500)
        let plan = TranscriptionChunker.chunk(
            buffer: buf,
            segments: [SpeechSegment(start: 400, end: 9000)],
            config: config()
        )
        XCTAssertEqual(plan.chunks.count, 1)
        XCTAssertEqual(plan.chunks[0].samples.count, 100)
        XCTAssertEqual(plan.chunks[0].endSample, 500)
    }
}

/// Tests for the pure transcript stitching logic (`TranscriptStitcher`).
final class TranscriptStitcherTests: XCTestCase {

    func testEmptyInputYieldsEmptyString() {
        XCTAssertEqual(TranscriptStitcher.stitch([]), "")
    }

    func testAllEmptyPiecesYieldsEmptyString() {
        XCTAssertEqual(TranscriptStitcher.stitch(["", "   ", "\n"]), "")
    }

    func testSinglePieceIsTrimmed() {
        XCTAssertEqual(TranscriptStitcher.stitch(["  hello world  "]), "hello world")
    }

    func testJoinsWithSingleSpace() {
        XCTAssertEqual(
            TranscriptStitcher.stitch(["hello", "world"]),
            "hello world"
        )
    }

    func testSkipsEmptyPieces() {
        XCTAssertEqual(
            TranscriptStitcher.stitch(["hello", "", "  ", "world"]),
            "hello world"
        )
    }

    func testCollapsesDoubledWhitespaceAtSeam() {
        XCTAssertEqual(
            TranscriptStitcher.stitch(["hello ", " world"]),
            "hello world"
        )
    }

    func testCollapsesDoubledTerminalPunctuationAtSeam() {
        XCTAssertEqual(
            TranscriptStitcher.stitch(["This is done.", ". And more"]),
            "This is done. And more"
        )
    }

    func testCollapsesAdjacentPunctuationWithoutSpace() {
        XCTAssertEqual(
            TranscriptStitcher.stitch(["Wait..", "really"]),
            "Wait. really"
        )
    }

    func testPreservesInternalPunctuation() {
        XCTAssertEqual(
            TranscriptStitcher.stitch(["one, two, three.", "Four."]),
            "one, two, three. Four."
        )
    }
}
