import Foundation

/// Runs Silero VAD (via whisper.cpp's native GGML runtime) over a recorded
/// buffer and returns a speech-only buffer plus the sample-indexed speech
/// segments that produced it.
///
/// The deterministic hysteresis / padding / merging logic lives in the pure
/// `VADSegmentBuilder`; this type is the thin bridge to the C runtime, owns the
/// VAD context lifecycle, and emits diagnostic events. It never throws: any
/// failure (missing model, load error, detection error) degrades to passing the
/// unfiltered buffer through so a recording is never lost.
final class VADProcessor: @unchecked Sendable {
    /// Minimum samples Silero needs to produce at least one frame (512 samples
    /// at 16 kHz). Shorter buffers bypass VAD entirely.
    private static let minimumSamples = 512

    private let modelPath: String
    private let config: VADConfig
    private let useGPU: Bool
    private nonisolated(unsafe) var vadContext: OpaquePointer?

    // VAD always defaults to CPU: the Silero VAD graph aborts inside
    // `ggml_backend_sched` when allocated on the Metal backend in the bundled
    // whisper.cpp build (ggml_abort in ggml_backend_sched_backend_id_from_cur),
    // crashing the app. The model is tiny, so CPU has no meaningful cost.
    init(modelPath: String, config: VADConfig = .default, useGPU: Bool = false) {
        self.modelPath = modelPath
        self.config = config
        self.useGPU = useGPU
    }

    deinit {
        if let vadContext { whisper_vad_free(vadContext) }
    }

    struct Result {
        /// Speech-only audio. Empty when no speech was detected.
        let filtered: [Float]
        /// Sample-indexed speech segments in the original buffer. Empty when no
        /// speech was detected.
        let segments: [SpeechSegment]
    }

    /// Filters a 16 kHz mono Float32 buffer down to its speech-bearing
    /// segments.
    func process(_ samples: [Float]) -> Result {
        PipelineEventLog.shared.append("🎚️ vad.started — \(samples.count) samples")

        // A buffer shorter than one VAD frame cannot be analysed; pass it
        // through unchanged so very short utterances are never dropped.
        guard samples.count >= Self.minimumSamples else {
            return passthrough(samples, reason: nil)
        }

        guard let context = ensureContext() else {
            return passthrough(samples, reason: "vad.unavailable — model unavailable")
        }

        let detected = samples.withUnsafeBufferPointer { buffer in
            whisper_vad_detect_speech(context, buffer.baseAddress, Int32(samples.count))
        }
        guard detected else {
            return passthrough(samples, reason: "vad.unavailable — detection failed")
        }

        let probCount = Int(whisper_vad_n_probs(context))
        guard probCount > 0, let probsPtr = whisper_vad_probs(context) else {
            return passthrough(samples, reason: "vad.unavailable — no probabilities")
        }

        let probabilities = Array(UnsafeBufferPointer(start: probsPtr, count: probCount))
        let frameSamples = max(1, samples.count / probCount)
        let segments = VADSegmentBuilder.buildSegments(
            probabilities: probabilities,
            frameSamples: frameSamples,
            totalSamples: samples.count,
            config: config
        )

        guard !segments.isEmpty else {
            PipelineEventLog.shared.append("🤫 vad.no_speech_detected", kind: .info)
            return Result(filtered: [], segments: [])
        }

        let filtered = VADSegmentBuilder.filteredBuffer(from: samples, segments: segments)
        let keptMs = filtered.count * 1000 / 16_000
        let droppedMs = (samples.count - filtered.count) * 1000 / 16_000
        PipelineEventLog.shared.append(
            "✂️ vad.completed segments=\(segments.count) kept_ms=\(keptMs) dropped_ms=\(droppedMs)",
            kind: .success
        )
        return Result(filtered: filtered, segments: segments)
    }

    // MARK: - Private

    /// Lazily initialises the VAD context. Returns nil on any failure.
    private func ensureContext() -> OpaquePointer? {
        if let vadContext { return vadContext }
        guard FileManager.default.fileExists(atPath: modelPath) else { return nil }

        var contextParams = whisper_vad_default_context_params()
        contextParams.use_gpu = useGPU
        // Single-threaded on purpose. The Silero graph is tiny (0.88 MB) and is
        // evaluated once per 512-sample frame, so ggml's per-op thread barrier
        // dominates any parallel gain. Measured on an M4 Pro with a 15 s clip:
        // 1 thread ≈ 34 ms, 4 threads ≈ 66 ms, 13 threads (cores − 1) ≈ 273 s —
        // the latter made every dictation appear to hang forever.
        contextParams.n_threads = 1

        guard let context = whisper_vad_init_from_file_with_params(modelPath, contextParams) else {
            return nil
        }
        vadContext = context
        return context
    }

    /// Returns the input unchanged as a single full-span segment, optionally
    /// logging a degradation reason.
    private func passthrough(_ samples: [Float], reason: String?) -> Result {
        if let reason {
            PipelineEventLog.shared.append("⚠️ \(reason) — passing unfiltered audio", kind: .error)
        }
        guard !samples.isEmpty else { return Result(filtered: [], segments: []) }
        return Result(filtered: samples, segments: [SpeechSegment(start: 0, end: samples.count)])
    }
}
