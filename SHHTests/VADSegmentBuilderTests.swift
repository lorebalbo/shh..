import XCTest

/// Tests for the pure VAD segment-building logic (`VADSegmentBuilder`), which
/// converts per-frame Silero speech probabilities into merged, padded,
/// sample-indexed speech segments. These tests are deterministic and require no
/// whisper.cpp runtime. The types under test are compiled directly into the
/// test target.
final class VADSegmentBuilderTests: XCTestCase {

    private let frameSamples = 512

    /// Builds a probability array: `1.0` for speech frames, `0.0` otherwise.
    private func probs(_ pattern: [Bool]) -> [Float] {
        pattern.map { $0 ? 1.0 : 0.0 }
    }

    /// Config with no padding so raw frame→sample math is easy to assert.
    private func config(onset: Int = 2, offset: Int = 19, padding: Int = 0) -> VADConfig {
        VADConfig(speechThreshold: 0.5, onsetFrames: onset, offsetFrames: offset, paddingSamples: padding)
    }

    // MARK: - Degenerate inputs

    func testEmptyProbabilitiesYieldsNoSegments() {
        let segments = VADSegmentBuilder.buildSegments(
            probabilities: [],
            frameSamples: frameSamples,
            totalSamples: 16_000,
            config: config()
        )
        XCTAssertTrue(segments.isEmpty)
    }

    func testZeroTotalSamplesYieldsNoSegments() {
        let segments = VADSegmentBuilder.buildSegments(
            probabilities: probs([true, true, true]),
            frameSamples: frameSamples,
            totalSamples: 0,
            config: config()
        )
        XCTAssertTrue(segments.isEmpty)
    }

    // MARK: - Pure silence / pure speech

    func testPureSilenceYieldsNoSegments() {
        let pattern = Array(repeating: false, count: 100)
        let segments = VADSegmentBuilder.buildSegments(
            probabilities: probs(pattern),
            frameSamples: frameSamples,
            totalSamples: 100 * frameSamples,
            config: config()
        )
        XCTAssertTrue(segments.isEmpty)
    }

    func testPureSpeechYieldsSingleFullSpanSegment() {
        let frames = 100
        let total = frames * frameSamples
        let segments = VADSegmentBuilder.buildSegments(
            probabilities: probs(Array(repeating: true, count: frames)),
            frameSamples: frameSamples,
            totalSamples: total,
            config: config()
        )
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.start, 0)
        XCTAssertEqual(segments.first?.end, total)
    }

    // MARK: - Hysteresis: short vs long pause

    func testShortPauseDoesNotSplitSegment() {
        // 30 speech, 10-frame pause (< 19 offset), 30 speech.
        let pattern = Array(repeating: true, count: 30)
            + Array(repeating: false, count: 10)
            + Array(repeating: true, count: 30)
        let total = pattern.count * frameSamples
        let segments = VADSegmentBuilder.buildSegments(
            probabilities: probs(pattern),
            frameSamples: frameSamples,
            totalSamples: total,
            config: config()
        )
        XCTAssertEqual(segments.count, 1, "A sub-offset pause must not split the segment")
        XCTAssertEqual(segments.first?.start, 0)
        XCTAssertEqual(segments.first?.end, total)
    }

    func testLongPauseSplitsIntoTwoSegments() {
        // 30 speech, 25-frame pause (>= 19 offset), 30 speech.
        let speechA = 30
        let pause = 25
        let speechB = 30
        let pattern = Array(repeating: true, count: speechA)
            + Array(repeating: false, count: pause)
            + Array(repeating: true, count: speechB)
        let total = pattern.count * frameSamples
        let segments = VADSegmentBuilder.buildSegments(
            probabilities: probs(pattern),
            frameSamples: frameSamples,
            totalSamples: total,
            config: config()
        )
        XCTAssertEqual(segments.count, 2, "A pause exceeding the offset must split into two segments")
        // First segment ends where the offset run started (frame == speechA).
        XCTAssertEqual(segments[0].start, 0)
        XCTAssertEqual(segments[0].end, speechA * frameSamples)
        // Second segment starts at the resumed speech frame.
        XCTAssertEqual(segments[1].start, (speechA + pause) * frameSamples)
        XCTAssertEqual(segments[1].end, total)
    }

    // MARK: - Onset hysteresis

    func testSingleFrameSpikeIsIgnored() {
        // A single speech-positive frame surrounded by silence: below onset of 2.
        let pattern = Array(repeating: false, count: 10)
            + [true]
            + Array(repeating: false, count: 10)
        let segments = VADSegmentBuilder.buildSegments(
            probabilities: probs(pattern),
            frameSamples: frameSamples,
            totalSamples: pattern.count * frameSamples,
            config: config()
        )
        XCTAssertTrue(segments.isEmpty, "A single-frame spike must not open a segment")
    }

    // MARK: - Padding & merge

    func testPaddingExtendsSegmentAndClampsToBounds() {
        // Speech occupies frames 5..<15; padding should extend each side but
        // never exceed [0, total].
        let pattern = Array(repeating: false, count: 5)
            + Array(repeating: true, count: 10)
            + Array(repeating: false, count: 5)
        let total = pattern.count * frameSamples
        let padding = 1600
        let segments = VADSegmentBuilder.buildSegments(
            probabilities: probs(pattern),
            frameSamples: frameSamples,
            totalSamples: total,
            config: config(offset: 3, padding: padding)
        )
        XCTAssertEqual(segments.count, 1)
        let raw = SpeechSegment(start: 5 * frameSamples, end: 15 * frameSamples)
        XCTAssertEqual(segments[0].start, max(0, raw.start - padding))
        XCTAssertEqual(segments[0].end, min(total, raw.end + padding))
    }

    func testPaddingMergesAdjacentSegments() {
        // Two speech bursts separated by exactly the offset; with large padding
        // the padded spans overlap and must merge back into one.
        let pattern = Array(repeating: true, count: 20)
            + Array(repeating: false, count: 19)
            + Array(repeating: true, count: 20)
        let total = pattern.count * frameSamples
        // Padding larger than the gap (19 frames * 512) forces a merge.
        let padding = 19 * frameSamples
        let segments = VADSegmentBuilder.buildSegments(
            probabilities: probs(pattern),
            frameSamples: frameSamples,
            totalSamples: total,
            config: config(offset: 19, padding: padding)
        )
        XCTAssertEqual(segments.count, 1, "Overlapping padded segments must merge")
        XCTAssertEqual(segments[0].start, 0)
        XCTAssertEqual(segments[0].end, total)
    }

    // MARK: - filteredBuffer

    func testFilteredBufferConcatenatesSegmentSamples() {
        let source = (0..<100).map { Float($0) }
        let segments = [
            SpeechSegment(start: 10, end: 20),
            SpeechSegment(start: 40, end: 45)
        ]
        let filtered = VADSegmentBuilder.filteredBuffer(from: source, segments: segments)
        XCTAssertEqual(filtered.count, 15)
        XCTAssertEqual(filtered.first, 10)
        XCTAssertEqual(filtered.last, 44)
    }

    func testFilteredBufferClampsOutOfBoundsSegments() {
        let source = (0..<10).map { Float($0) }
        let segments = [SpeechSegment(start: 5, end: 999)]
        let filtered = VADSegmentBuilder.filteredBuffer(from: source, segments: segments)
        XCTAssertEqual(filtered, [5, 6, 7, 8, 9])
    }

    func testFilteredBufferEmptySegmentsYieldsEmpty() {
        let source = (0..<10).map { Float($0) }
        XCTAssertTrue(VADSegmentBuilder.filteredBuffer(from: source, segments: []).isEmpty)
    }
}
