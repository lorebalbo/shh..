import XCTest

/// Unit tests for the pure benchmark types: text normalization, WER, RTFx
/// arithmetic, aggregation and report comparison. None depend on whisper.cpp,
/// so they run in the standard unit-test target.
final class BenchmarkMetricsTests: XCTestCase {

    // MARK: - WhisperTextNormalizer

    func testNormalizeLowercasesAndStripsPunctuation() {
        XCTAssertEqual(
            WhisperTextNormalizer.normalize("Hello, World!"),
            "hello world"
        )
    }

    func testNormalizeCollapsesWhitespace() {
        XCTAssertEqual(
            WhisperTextNormalizer.normalize("  the   quick \t brown\nfox "),
            "the quick brown fox"
        )
    }

    func testNormalizeExpandsContractions() {
        XCTAssertEqual(WhisperTextNormalizer.normalize("I can't do it"), "i cannot do it")
        XCTAssertEqual(WhisperTextNormalizer.normalize("We won't go"), "we will not go")
        XCTAssertEqual(WhisperTextNormalizer.normalize("It's fine"), "it is fine")
    }

    func testNormalizeMapsNumberWordsToDigits() {
        XCTAssertEqual(WhisperTextNormalizer.normalize("there were three cats"), "there were 3 cats")
        XCTAssertEqual(WhisperTextNormalizer.normalize("twenty"), "20")
    }

    func testTokensSplitsOnSpaces() {
        XCTAssertEqual(WhisperTextNormalizer.tokens("Hello, World!"), ["hello", "world"])
    }

    // MARK: - WERCalculator

    func testPerfectMatchIsZeroWER() {
        let result = WERCalculator.compute(reference: ["a", "b", "c"], hypothesis: ["a", "b", "c"])
        XCTAssertEqual(result.wer, 0.0)
        XCTAssertEqual(result.substitutions, 0)
        XCTAssertEqual(result.deletions, 0)
        XCTAssertEqual(result.insertions, 0)
    }

    func testSingleSubstitutionIsOneOverN() {
        let result = WERCalculator.compute(reference: ["a", "b", "c"], hypothesis: ["a", "x", "c"])
        XCTAssertEqual(result.substitutions, 1)
        XCTAssertEqual(result.wer, 1.0 / 3.0)
    }

    func testSingleDeletionIsOneOverN() {
        let result = WERCalculator.compute(reference: ["a", "b", "c"], hypothesis: ["a", "c"])
        XCTAssertEqual(result.deletions, 1)
        XCTAssertEqual(result.wer, 1.0 / 3.0)
    }

    func testSingleInsertionIsOneOverN() {
        let result = WERCalculator.compute(reference: ["a", "b", "c"], hypothesis: ["a", "b", "x", "c"])
        XCTAssertEqual(result.insertions, 1)
        XCTAssertEqual(result.wer, 1.0 / 3.0)
    }

    func testEmptyHypothesisIsFullWER() {
        let result = WERCalculator.compute(reference: ["a", "b", "c"], hypothesis: [])
        XCTAssertEqual(result.deletions, 3)
        XCTAssertEqual(result.wer, 1.0)
    }

    func testEmptyReferenceIsUndefinedWER() {
        let result = WERCalculator.compute(reference: [], hypothesis: ["a", "b"])
        XCTAssertEqual(result.referenceWords, 0)
        XCTAssertNil(result.wer)
    }

    func testWERFromTextNormalizesBeforeComparing() {
        let result = WERCalculator.compute(
            referenceText: "The quick brown fox.",
            hypothesisText: "the Quick brown FOX"
        )
        XCTAssertEqual(result.wer, 0.0)
    }

    // MARK: - RTFxMeasurer

    func testRTFxArithmetic() {
        XCTAssertEqual(RTFxMeasurer.rtfx(audioSeconds: 10, elapsedSeconds: 2), 5.0)
        XCTAssertEqual(RTFxMeasurer.rtfx(audioSeconds: 4, elapsedSeconds: 8), 0.5)
    }

    func testRTFxZeroElapsedIsNil() {
        XCTAssertNil(RTFxMeasurer.rtfx(audioSeconds: 10, elapsedSeconds: 0))
    }

    func testMeasureWrapsValueAndDurations() {
        let measurement = RTFxMeasurer.measure(audioSeconds: 5) { 42 }
        XCTAssertEqual(measurement.value, 42)
        XCTAssertEqual(measurement.audioSeconds, 5)
        XCTAssertGreaterThanOrEqual(measurement.elapsedSeconds, 0)
    }

    // MARK: - Aggregation

    func testAggregateMicroAveragesWER() {
        let files = [
            BenchmarkReport.FileResult(
                file: "a.wav", audioSeconds: 10, transcribeSeconds: 2, rtfx: 5,
                wer: 0.1, referenceWords: 10, substitutions: 1, deletions: 0,
                insertions: 0, failed: false
            ),
            BenchmarkReport.FileResult(
                file: "b.wav", audioSeconds: 20, transcribeSeconds: 5, rtfx: 4,
                wer: 0.2, referenceWords: 10, substitutions: 0, deletions: 2,
                insertions: 0, failed: false
            ),
        ]
        let aggregate = BenchmarkAggregator.aggregate(files)
        // Micro-average: (1 + 2) edits / (10 + 10) words = 0.15
        XCTAssertEqual(aggregate.wer, 0.15)
        // Weighted RTFx: 30 audio / 7 transcribe.
        XCTAssertEqual(aggregate.rtfx, 30.0 / 7.0)
        XCTAssertEqual(aggregate.failedFiles, 0)
    }

    func testAggregateExcludesFailedFiles() {
        let files = [
            BenchmarkReport.FileResult(
                file: "ok.wav", audioSeconds: 10, transcribeSeconds: 2, rtfx: 5,
                wer: 0.1, referenceWords: 10, substitutions: 1, deletions: 0,
                insertions: 0, failed: false
            ),
            BenchmarkReport.FileResult(
                file: "bad.wav", audioSeconds: 0, transcribeSeconds: 0, rtfx: nil,
                wer: nil, referenceWords: 0, substitutions: 0, deletions: 0,
                insertions: 0, failed: true
            ),
        ]
        let aggregate = BenchmarkAggregator.aggregate(files)
        XCTAssertEqual(aggregate.wer, 0.1)
        XCTAssertEqual(aggregate.failedFiles, 1)
        XCTAssertEqual(aggregate.totalFiles, 2)
    }

    // MARK: - Comparison

    private func makeReport(wer: Double, files: [BenchmarkReport.FileResult]) -> BenchmarkReport {
        BenchmarkReport(
            gitSHA: "abc123",
            modelName: "ggml-test.bin",
            decodeConfig: BenchmarkReport.DecodeConfigSnapshot(
                temperatures: [0], compressionRatioThreshold: 2.4, logprobThreshold: -1,
                noSpeechThreshold: 0.9, conditionOnPreviousText: true, beamSize: 5
            ),
            host: BenchmarkReport.HostInfo(osVersion: "test", cpuCores: 8, physicalMemoryBytes: 0),
            files: files,
            aggregate: BenchmarkAggregator.aggregate(files)
        )
    }

    func testComparisonFlagsRegressionBeyondThreshold() {
        let before = makeReport(wer: 0.10, files: [
            BenchmarkReport.FileResult(
                file: "a.wav", audioSeconds: 10, transcribeSeconds: 2, rtfx: 5,
                wer: 0.10, referenceWords: 100, substitutions: 10, deletions: 0,
                insertions: 0, failed: false
            ),
        ])
        let after = makeReport(wer: 0.12, files: [
            BenchmarkReport.FileResult(
                file: "a.wav", audioSeconds: 10, transcribeSeconds: 2, rtfx: 5,
                wer: 0.12, referenceWords: 100, substitutions: 12, deletions: 0,
                insertions: 0, failed: false
            ),
        ])
        let verdict = BenchmarkComparison.compare(before: before, after: after, thresholdPP: 0.5)
        // 2pp regression > 0.5pp threshold.
        XCTAssertTrue(verdict.regressed)
        XCTAssertEqual(verdict.werDeltaPP ?? 0, 2.0, accuracy: 0.0001)
    }

    func testComparisonAcceptsImprovement() {
        let before = makeReport(wer: 0.12, files: [
            BenchmarkReport.FileResult(
                file: "a.wav", audioSeconds: 10, transcribeSeconds: 2, rtfx: 5,
                wer: 0.12, referenceWords: 100, substitutions: 12, deletions: 0,
                insertions: 0, failed: false
            ),
        ])
        let after = makeReport(wer: 0.08, files: [
            BenchmarkReport.FileResult(
                file: "a.wav", audioSeconds: 10, transcribeSeconds: 2, rtfx: 5,
                wer: 0.08, referenceWords: 100, substitutions: 8, deletions: 0,
                insertions: 0, failed: false
            ),
        ])
        let verdict = BenchmarkComparison.compare(before: before, after: after)
        XCTAssertFalse(verdict.regressed)
        XCTAssertEqual(verdict.fileDeltas.first?.werDelta ?? 0, -0.04, accuracy: 0.0001)
    }

    // MARK: - Report round-trips through JSON

    func testReportEncodesAndDecodes() throws {
        let report = makeReport(wer: 0.1, files: [
            BenchmarkReport.FileResult(
                file: "a.wav", audioSeconds: 10, transcribeSeconds: 2, rtfx: 5,
                wer: 0.1, referenceWords: 10, substitutions: 1, deletions: 0,
                insertions: 0, failed: false
            ),
        ])
        let data = try JSONEncoder().encode(report)
        let decoded = try JSONDecoder().decode(BenchmarkReport.self, from: data)
        XCTAssertEqual(decoded, report)
    }
}
