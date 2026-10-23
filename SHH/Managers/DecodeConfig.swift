import Foundation
import Compression

/// Decoder configuration for a single chunk's Whisper transcription, including
/// the temperature fallback ladder and the confidence thresholds that trigger
/// it. Defaults mirror OpenAI's upstream Whisper values that exist specifically
/// to combat looping and low-likelihood hallucinations.
struct DecodeConfig: Equatable {
    /// Temperature ladder tried in order. The first attempt that passes both
    /// confidence checks wins; if none pass, the last (highest-temperature)
    /// attempt is kept. Mirrors OpenAI's
    /// `temperatures = [0.0, 0.2, 0.4, 0.6, 0.8, 1.0]`.
    var temperatures: [Float]

    /// Upper bound on text compression ratio (text bytes / zlib bytes). A run
    /// of repeated phrases ("thank you. thank you. ...") compresses extremely
    /// well, pushing the ratio above this bound and triggering fallback.
    /// Mirrors OpenAI's `compression_ratio_threshold = 2.4`.
    var compressionRatioThreshold: Float

    /// Lower bound on the average per-token log probability. Segments below
    /// this are low-likelihood and trigger fallback. Mirrors OpenAI's
    /// `logprob_threshold = -1.0`.
    var logprobThreshold: Float

    /// `no_speech` probability above which Whisper discards a window's text.
    /// Kept at 0.9 (vs. upstream 0.6): with VAD + chunking a chunk may still
    /// contain a long internal pause, and the higher bound prevents Whisper
    /// from dropping real speech that shares a window with that pause.
    var noSpeechThreshold: Float

    /// When true, the previous confident chunk's tail tokens are fed as the
    /// next chunk's `initial_prompt` for cross-chunk continuity. Suppressed
    /// automatically after a chunk exhausts its fallback ladder.
    var conditionOnPreviousText: Bool

    /// Beam width used for the temperature-0 (beam search) attempt. Non-zero
    /// temperatures use sampling instead, matching upstream behaviour.
    var beamSize: Int

    /// Optional prompt prepended to bias the decode (previous-chunk tail).
    var initialPrompt: String

    static let `default` = DecodeConfig(
        temperatures: [0.0, 0.2, 0.4, 0.6, 0.8, 1.0],
        compressionRatioThreshold: 2.4,
        logprobThreshold: -1.0,
        noSpeechThreshold: 0.9,
        conditionOnPreviousText: true,
        beamSize: 5,
        initialPrompt: ""
    )

    init(
        temperatures: [Float],
        compressionRatioThreshold: Float,
        logprobThreshold: Float,
        noSpeechThreshold: Float,
        conditionOnPreviousText: Bool,
        beamSize: Int,
        initialPrompt: String
    ) {
        self.temperatures = temperatures.isEmpty ? [0.0] : temperatures
        self.compressionRatioThreshold = compressionRatioThreshold
        self.logprobThreshold = logprobThreshold
        self.noSpeechThreshold = noSpeechThreshold
        self.conditionOnPreviousText = conditionOnPreviousText
        self.beamSize = max(1, beamSize)
        self.initialPrompt = initialPrompt
    }
}

/// The outcome of decoding a single chunk after running the fallback ladder.
struct DecodeResult: Equatable {
    let text: String
    /// Temperature of the accepted (or last) attempt.
    let temperature: Float
    let compressionRatio: Float
    let avgLogprob: Float
    /// True when no attempt passed the confidence checks and the highest
    /// temperature's output was kept as a best-effort result.
    let fallbackExhausted: Bool
}

/// One raw attempt produced by the (whisper-dependent) decode closure, before
/// confidence evaluation.
struct DecodeAttempt: Equatable {
    let text: String
    let temperature: Float
    let avgLogprob: Float
}

/// Pure, deterministic decoder-confidence logic. Free of any whisper.cpp
/// dependency so the compression-ratio computation, the accept/reject decision,
/// and the temperature-ladder driver can all be unit tested directly.
enum DecodeQuality {
    /// Computes the gzip-style compression ratio (UTF-8 byte length divided by
    /// zlib-compressed byte length). Repetitive, hallucinated text compresses
    /// far better than natural speech, yielding a high ratio. Empty/whitespace
    /// text returns 0 so it never trips the threshold.
    static func compressionRatio(of text: String) -> Float {
        let bytes = Array(text.utf8)
        guard bytes.count > 0 else { return 0 }

        let destinationSize = bytes.count + 64
        var destination = [UInt8](repeating: 0, count: destinationSize)
        let compressedCount = destination.withUnsafeMutableBufferPointer { dst in
            bytes.withUnsafeBufferPointer { src in
                compression_encode_buffer(
                    dst.baseAddress!, destinationSize,
                    src.baseAddress!, bytes.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        // compression_encode_buffer returns 0 if the output did not fit; fall
        // back to the raw byte count to avoid a divide-by-zero.
        let denominator = compressedCount > 0 ? compressedCount : bytes.count
        return Float(bytes.count) / Float(denominator)
    }

    /// True when both confidence signals are within bounds: compression ratio
    /// below the threshold (not a repetition loop) and average log probability
    /// above the threshold (not low-likelihood).
    static func isAcceptable(
        compressionRatio: Float,
        avgLogprob: Float,
        config: DecodeConfig
    ) -> Bool {
        compressionRatio <= config.compressionRatioThreshold
            && avgLogprob >= config.logprobThreshold
    }
}

/// Drives the temperature fallback ladder using a caller-supplied decode
/// closure. Pure and synchronous: the closure performs the actual (possibly
/// whisper-backed) decode, while this driver owns the accept/reject and
/// retry policy so it can be tested without the native runtime.
enum TemperatureFallback {
    /// Runs the ladder, returning the first accepted attempt or — if none pass
    /// — the last attempt with `fallbackExhausted = true`.
    ///
    /// - Parameters:
    ///   - config: Thresholds and the temperature ladder.
    ///   - decode: Produces a `DecodeAttempt` for a given temperature.
    static func run(
        config: DecodeConfig,
        decode: (Float) -> DecodeAttempt
    ) -> DecodeResult {
        var last: DecodeResult?
        for temperature in config.temperatures {
            let attempt = decode(temperature)
            let ratio = DecodeQuality.compressionRatio(of: attempt.text)
            let accepted = DecodeQuality.isAcceptable(
                compressionRatio: ratio,
                avgLogprob: attempt.avgLogprob,
                config: config
            )
            let result = DecodeResult(
                text: attempt.text,
                temperature: attempt.temperature,
                compressionRatio: ratio,
                avgLogprob: attempt.avgLogprob,
                fallbackExhausted: false
            )
            if accepted {
                return result
            }
            last = result
        }

        // No attempt passed — keep the highest-temperature output as a
        // best-effort result and flag the exhaustion.
        let fallback = last ?? DecodeResult(
            text: "", temperature: config.temperatures.last ?? 0,
            compressionRatio: 0, avgLogprob: 0, fallbackExhausted: true
        )
        return DecodeResult(
            text: fallback.text,
            temperature: fallback.temperature,
            compressionRatio: fallback.compressionRatio,
            avgLogprob: fallback.avgLogprob,
            fallbackExhausted: true
        )
    }
}
