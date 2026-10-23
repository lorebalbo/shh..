import XCTest

/// Tests for the pure decoder-confidence logic: compression-ratio computation,
/// the accept/reject decision, and the temperature fallback ladder driver.
/// All are free of any whisper.cpp runtime dependency.
final class DecodeFallbackTests: XCTestCase {

    private func config(
        temperatures: [Float] = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
        compression: Float = 2.4,
        logprob: Float = -1.0
    ) -> DecodeConfig {
        DecodeConfig(
            temperatures: temperatures,
            compressionRatioThreshold: compression,
            logprobThreshold: logprob,
            noSpeechThreshold: 0.9,
            conditionOnPreviousText: true,
            beamSize: 5,
            initialPrompt: ""
        )
    }

    // MARK: - Default spec

    func testDefaultConfigMatchesDocumentedSpec() {
        let c = DecodeConfig.default
        XCTAssertEqual(c.temperatures, [0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
        XCTAssertEqual(c.compressionRatioThreshold, 2.4)
        XCTAssertEqual(c.logprobThreshold, -1.0)
        XCTAssertEqual(c.noSpeechThreshold, 0.9)
        XCTAssertTrue(c.conditionOnPreviousText)
        XCTAssertEqual(c.beamSize, 5)
        XCTAssertEqual(c.initialPrompt, "")
    }

    func testEmptyTemperaturesFallsBackToZero() {
        let c = config(temperatures: [])
        XCTAssertEqual(c.temperatures, [0.0])
    }

    // MARK: - Compression ratio

    func testCompressionRatioEmptyTextIsZero() {
        XCTAssertEqual(DecodeQuality.compressionRatio(of: ""), 0)
    }

    func testRepetitiveTextHasHighCompressionRatio() {
        let looped = String(repeating: "thank you. ", count: 40)
        let ratio = DecodeQuality.compressionRatio(of: looped)
        XCTAssertGreaterThan(ratio, 2.4)
    }

    func testNaturalTextHasLowCompressionRatio() {
        let natural = "The quick brown fox jumps over the lazy dog near the riverbank at dawn."
        let ratio = DecodeQuality.compressionRatio(of: natural)
        XCTAssertLessThan(ratio, 2.4)
    }

    // MARK: - Acceptance decision

    func testAcceptsWhenBothSignalsWithinBounds() {
        XCTAssertTrue(
            DecodeQuality.isAcceptable(compressionRatio: 1.8, avgLogprob: -0.3, config: config())
        )
    }

    func testRejectsWhenCompressionTooHigh() {
        XCTAssertFalse(
            DecodeQuality.isAcceptable(compressionRatio: 3.0, avgLogprob: -0.3, config: config())
        )
    }

    func testRejectsWhenLogprobTooLow() {
        XCTAssertFalse(
            DecodeQuality.isAcceptable(compressionRatio: 1.8, avgLogprob: -1.5, config: config())
        )
    }

    // MARK: - Temperature fallback ladder

    func testPassingConfigRunsExactlyOneAttempt() {
        var attempts: [Float] = []
        let result = TemperatureFallback.run(config: config()) { temperature in
            attempts.append(temperature)
            return DecodeAttempt(text: "hello world this is fine", temperature: temperature, avgLogprob: -0.2)
        }
        XCTAssertEqual(attempts, [0.0])
        XCTAssertEqual(result.temperature, 0.0)
        XCTAssertFalse(result.fallbackExhausted)
        XCTAssertEqual(result.text, "hello world this is fine")
    }

    func testFailingCompressionRetriesUpTheLadder() {
        // Always return a looping (high-compression) string so every attempt
        // fails the compression check and the ladder runs to exhaustion.
        var attempts: [Float] = []
        let looped = String(repeating: "thank you. ", count: 40)
        let result = TemperatureFallback.run(config: config()) { temperature in
            attempts.append(temperature)
            return DecodeAttempt(text: looped, temperature: temperature, avgLogprob: -0.2)
        }
        XCTAssertEqual(attempts, [0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
        XCTAssertTrue(result.fallbackExhausted)
        XCTAssertEqual(result.temperature, 1.0)
    }

    func testStopsAtFirstPassingTemperature() {
        // Fail at 0.0 and 0.2, pass at 0.4.
        var attempts: [Float] = []
        let looped = String(repeating: "thank you. ", count: 40)
        let result = TemperatureFallback.run(config: config()) { temperature in
            attempts.append(temperature)
            if temperature < 0.4 {
                return DecodeAttempt(text: looped, temperature: temperature, avgLogprob: -0.2)
            }
            return DecodeAttempt(text: "a clean natural sentence here", temperature: temperature, avgLogprob: -0.2)
        }
        XCTAssertEqual(attempts, [0.0, 0.2, 0.4])
        XCTAssertFalse(result.fallbackExhausted)
        XCTAssertEqual(result.temperature, 0.4)
        XCTAssertEqual(result.text, "a clean natural sentence here")
    }

    func testLogprobFailureAlsoTriggersFallback() {
        var attempts: [Float] = []
        let result = TemperatureFallback.run(config: config()) { temperature in
            attempts.append(temperature)
            // Natural text (low compression) but very low log probability.
            return DecodeAttempt(text: "natural sentence", temperature: temperature, avgLogprob: -2.0)
        }
        XCTAssertEqual(attempts.count, 6)
        XCTAssertTrue(result.fallbackExhausted)
    }
}
