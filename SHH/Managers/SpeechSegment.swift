import Foundation

/// A contiguous span of detected speech within an audio buffer, expressed in
/// sample indices (not seconds) so chunking and stitching downstream are
/// sample-accurate and free of rounding drift at boundaries.
struct SpeechSegment: Equatable {
    /// Inclusive start sample index in the original buffer.
    let start: Int
    /// Exclusive end sample index in the original buffer.
    let end: Int

    var sampleCount: Int { max(0, end - start) }

    init(start: Int, end: Int) {
        self.start = start
        self.end = end
    }
}

/// Tunable parameters for converting per-frame VAD speech probabilities into
/// merged, padded speech segments. The hysteresis constants are expressed in
/// frames; the Silero v5 model emits one probability per 512-sample frame at
/// 16 kHz (~32 ms), which is the basis for the defaults below.
struct VADConfig: Equatable {
    /// Probability at or above which a frame is considered speech-positive.
    var speechThreshold: Float

    /// N — number of consecutive speech-positive frames required to open a
    /// segment. Two frames (~64 ms) suppresses single-frame false positives
    /// (clicks, transient noise) without clipping real speech onsets.
    var onsetFrames: Int

    /// M — number of consecutive speech-negative frames required to close a
    /// segment. 19 frames (~608 ms at 32 ms/frame) is tuned so that
    /// mid-sentence thinking pauses of up to ~600 ms do NOT split a segment,
    /// while genuine end-of-thought pauses do.
    var offsetFrames: Int

    /// Symmetric padding (in samples) added to each side of every raw segment
    /// so Whisper sees a clean attack and release instead of a hard-clipped
    /// edge. 1600 samples == 100 ms at 16 kHz.
    var paddingSamples: Int

    static let `default` = VADConfig(
        speechThreshold: 0.5,
        onsetFrames: 2,
        offsetFrames: 19,
        paddingSamples: 1600
    )

    init(speechThreshold: Float, onsetFrames: Int, offsetFrames: Int, paddingSamples: Int) {
        self.speechThreshold = speechThreshold
        self.onsetFrames = max(1, onsetFrames)
        self.offsetFrames = max(1, offsetFrames)
        self.paddingSamples = max(0, paddingSamples)
    }
}

/// Pure, deterministic conversion of per-frame VAD probabilities into a list of
/// sample-indexed speech segments. This logic is intentionally free of any
/// dependency on the whisper.cpp C runtime so it can be exhaustively unit
/// tested without linking the native library.
enum VADSegmentBuilder {
    /// Builds merged, padded speech segments from per-frame speech
    /// probabilities using onset/offset hysteresis.
    ///
    /// - Parameters:
    ///   - probabilities: One speech probability per VAD frame, in order.
    ///   - frameSamples: Number of audio samples represented by each frame.
    ///   - totalSamples: Total length of the source buffer in samples (used to
    ///     clamp the final segment and padding to the real buffer bounds).
    ///   - config: Hysteresis and padding parameters.
    /// - Returns: Non-overlapping, ascending speech segments. Empty when no
    ///   speech crosses the hysteresis thresholds.
    static func buildSegments(
        probabilities: [Float],
        frameSamples: Int,
        totalSamples: Int,
        config: VADConfig = .default
    ) -> [SpeechSegment] {
        guard !probabilities.isEmpty, frameSamples > 0, totalSamples > 0 else {
            return []
        }

        var rawSegments: [SpeechSegment] = []
        var inSpeech = false
        var segmentStartFrame = 0
        var candidateStartFrame = 0
        var positiveRun = 0
        var negativeRun = 0

        for (frameIndex, probability) in probabilities.enumerated() {
            let isSpeech = probability >= config.speechThreshold

            if inSpeech {
                if isSpeech {
                    negativeRun = 0
                } else {
                    negativeRun += 1
                    if negativeRun >= config.offsetFrames {
                        // Speech ended at the first negative frame of this run.
                        let endFrame = frameIndex - config.offsetFrames + 1
                        rawSegments.append(
                            rawSegment(
                                startFrame: segmentStartFrame,
                                endFrame: endFrame,
                                frameSamples: frameSamples,
                                totalSamples: totalSamples
                            )
                        )
                        inSpeech = false
                        positiveRun = 0
                        negativeRun = 0
                    }
                }
            } else {
                if isSpeech {
                    if positiveRun == 0 { candidateStartFrame = frameIndex }
                    positiveRun += 1
                    if positiveRun >= config.onsetFrames {
                        inSpeech = true
                        segmentStartFrame = candidateStartFrame
                        negativeRun = 0
                    }
                } else {
                    positiveRun = 0
                }
            }
        }

        if inSpeech {
            rawSegments.append(
                rawSegment(
                    startFrame: segmentStartFrame,
                    endFrame: probabilities.count,
                    frameSamples: frameSamples,
                    totalSamples: totalSamples
                )
            )
        }

        return padAndMerge(rawSegments, paddingSamples: config.paddingSamples, totalSamples: totalSamples)
    }

    /// Concatenates the samples covered by `segments` from `source` into a
    /// single speech-only buffer.
    static func filteredBuffer(from source: [Float], segments: [SpeechSegment]) -> [Float] {
        guard !segments.isEmpty else { return [] }
        var out = [Float]()
        out.reserveCapacity(segments.reduce(0) { $0 + $1.sampleCount })
        for segment in segments {
            let start = max(0, min(segment.start, source.count))
            let end = max(start, min(segment.end, source.count))
            if end > start { out.append(contentsOf: source[start..<end]) }
        }
        return out
    }

    // MARK: - Private

    private static func rawSegment(
        startFrame: Int,
        endFrame: Int,
        frameSamples: Int,
        totalSamples: Int
    ) -> SpeechSegment {
        let start = max(0, min(startFrame * frameSamples, totalSamples))
        let end = max(start, min(endFrame * frameSamples, totalSamples))
        return SpeechSegment(start: start, end: end)
    }

    private static func padAndMerge(
        _ rawSegments: [SpeechSegment],
        paddingSamples: Int,
        totalSamples: Int
    ) -> [SpeechSegment] {
        guard !rawSegments.isEmpty else { return [] }

        let padded = rawSegments
            .map { segment in
                SpeechSegment(
                    start: max(0, segment.start - paddingSamples),
                    end: min(totalSamples, segment.end + paddingSamples)
                )
            }
            .sorted { $0.start < $1.start }

        var merged: [SpeechSegment] = []
        for segment in padded {
            if let last = merged.last, segment.start <= last.end {
                merged[merged.count - 1] = SpeechSegment(
                    start: last.start,
                    end: max(last.end, segment.end)
                )
            } else {
                merged.append(segment)
            }
        }
        return merged
    }
}
