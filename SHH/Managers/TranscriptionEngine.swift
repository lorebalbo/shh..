import Foundation

/// The shared VAD → chunk → decode → stitch orchestration used by both the
/// production `TranscriptionPipeline` and the benchmark CLI. Centralising the
/// flow here guarantees the benchmark measures exactly the code path the app
/// runs — no duplicated decode logic.
///
/// This type depends on the whisper-backed `WhisperTranscriber` / `VADProcessor`
/// and therefore lives in the app/benchmark targets only, never the unit-test
/// target. The deterministic sub-steps it calls (`VADSegmentBuilder`,
/// `TranscriptionChunker`, `DecodeQuality`, `TranscriptStitcher`) are themselves
/// independently unit-tested.
enum TranscriptionEngine {
    static let sampleRate = 16_000

    /// Runs the full transcription flow over a pre-normalized 16 kHz mono buffer.
    ///
    /// - Parameters:
    ///   - normalizedBuffer: Peak-normalized 16 kHz mono Float32 audio.
    ///   - transcriber: The whisper-backed decoder (one shared context).
    ///   - vad: Optional VAD processor. When nil, the whole buffer is treated
    ///     as a single speech segment.
    ///   - language: ISO 639-1 code or "auto".
    ///   - decodeConfig: Base decoder configuration; its `initialPrompt` is
    ///     managed per-chunk by this function.
    /// - Returns: The stitched transcript (empty when no speech was detected).
    static func run(
        normalizedBuffer: [Float],
        transcriber: WhisperTranscriber,
        vad: VADProcessor?,
        language: String = "auto",
        decodeConfig: DecodeConfig = .default
    ) throws -> String {
        guard !normalizedBuffer.isEmpty else { return "" }

        let segments: [SpeechSegment]
        if let vad {
            let result = vad.process(normalizedBuffer)
            if result.segments.isEmpty { return "" }
            segments = result.segments
        } else {
            segments = [SpeechSegment(start: 0, end: normalizedBuffer.count)]
        }

        let plan = TranscriptionChunker.chunk(buffer: normalizedBuffer, segments: segments)
        guard !plan.chunks.isEmpty else { return "" }

        let totalMs = plan.chunks.reduce(0) { $0 + $1.sampleCount } * 1000 / sampleRate
        PipelineEventLog.shared.append(
            "🧩 chunker.planned count=\(plan.chunks.count) total_ms=\(totalMs)",
            kind: .info
        )
        for splitIndex in plan.forcedSplitIndices {
            PipelineEventLog.shared.append("🪓 chunker.forced_split at_sample=\(splitIndex)", kind: .info)
        }

        var pieces: [String] = []
        var previousPrompt = ""
        var suppressPrompt = false
        for (index, chunk) in plan.chunks.enumerated() {
            var config = decodeConfig
            if config.conditionOnPreviousText, !suppressPrompt, !previousPrompt.isEmpty {
                config.initialPrompt = previousPrompt
            } else {
                config.initialPrompt = ""
                if suppressPrompt {
                    PipelineEventLog.shared.append(
                        "🚫 decoder.prompt_suppressed reason=prior_fallback_exhausted",
                        kind: .info
                    )
                }
            }

            let result = try transcriber.decode(
                audioBuffer: chunk.samples,
                language: language,
                config: config
            )

            if result.fallbackExhausted {
                PipelineEventLog.shared.append("🚧 decoder.fallback_exhausted chunk=\(index)", kind: .error)
            }

            if result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                PipelineEventLog.shared.append("🔇 chunker.empty_chunk_output index=\(index)", kind: .info)
                suppressPrompt = true
                continue
            }

            let chunkMs = chunk.sampleCount * 1000 / sampleRate
            PipelineEventLog.shared.append(
                "✅ chunker.chunk_completed index=\(index) ms=\(chunkMs)",
                kind: .success
            )
            pieces.append(result.text)

            if result.fallbackExhausted {
                suppressPrompt = true
                previousPrompt = ""
            } else {
                suppressPrompt = false
                previousPrompt = promptTail(from: result.text)
            }
        }

        let stitched = TranscriptStitcher.stitch(pieces)
        PipelineEventLog.shared.append(
            "🪡 chunker.stitched final_chars=\(stitched.count)",
            kind: .success
        )
        return stitched
    }

    /// Peak-normalizes a Float32 buffer to ~0.95 so Whisper receives clean,
    /// in-range samples. Handles both clipped (peak > 1.0) and quiet input.
    static func normalize(_ samples: [Float]) -> [Float] {
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        guard peak > 0.001 else { return samples }
        let scale = min(0.95 / peak, 10.0)
        return samples.map { $0 * scale }
    }

    /// Extracts the trailing words of a chunk's transcript to seed the next
    /// chunk's `initial_prompt`. Bounded so the prompt never grows unbounded.
    static func promptTail(from text: String, maxWords: Int = 32) -> String {
        let words = text.split(whereSeparator: { $0.isWhitespace })
        guard words.count > maxWords else { return text }
        return words.suffix(maxWords).joined(separator: " ")
    }
}
