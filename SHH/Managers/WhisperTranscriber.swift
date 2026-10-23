import Foundation

enum WhisperError: Error, LocalizedError {
    case modelNotFound(path: String)
    case modelLoadFailed(path: String)
    case contextCreationFailed
    case transcriptionFailed(reason: String)
    case emptyAudioBuffer

    var errorDescription: String? {
        switch self {
        case .modelNotFound(let path):
            return "Transcription model not found at path: \(path)"
        case .modelLoadFailed(let path):
            return "Failed to load transcription model from: \(path)"
        case .contextCreationFailed:
            return "Failed to create whisper context"
        case .transcriptionFailed(let reason):
            return "Transcription failed: \(reason)"
        case .emptyAudioBuffer:
            return "No audio data to transcribe"
        }
    }
}

final class WhisperTranscriber: @unchecked Sendable {
    private let modelPath: String
    private nonisolated(unsafe) let context: OpaquePointer

    init(modelPath: String) throws {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            throw WhisperError.modelNotFound(path: modelPath)
        }
        self.modelPath = modelPath

        var params = whisper_context_default_params()
        params.use_gpu = true

        guard let ctx = whisper_init_from_file_with_params(modelPath, params) else {
            throw WhisperError.modelLoadFailed(path: modelPath)
        }
        self.context = ctx
    }

    deinit {
        whisper_free(context)
    }

    /// Transcribes an audio buffer of 16kHz mono Float32 samples into text.
    /// - Parameters:
    ///   - audioBuffer: PCM audio samples at 16kHz, mono, Float32.
    ///   - language: ISO 639-1 language code (e.g. "en"), or "auto" for auto-detection.
    /// - Returns: The transcribed text string.
    func transcribe(audioBuffer: [Float], language: String = "auto") throws -> String {
        try decode(audioBuffer: audioBuffer, language: language, config: .default).text
    }

    /// Transcribes a chunk with a confidence-aware temperature fallback ladder.
    ///
    /// Runs the decode at the first temperature in `config.temperatures`; if the
    /// result fails the compression-ratio or average-log-probability checks it
    /// retries at the next temperature, keeping the first attempt that passes
    /// (or the highest-temperature attempt if none do). Returns the chosen text
    /// plus the confidence signals so callers can decide whether to condition
    /// the next chunk on this chunk's tokens.
    /// - Parameters:
    ///   - audioBuffer: PCM audio samples at 16kHz, mono, Float32.
    ///   - language: ISO 639-1 language code, or "auto".
    ///   - config: Decoder configuration (thresholds, ladder, prompt).
    func decode(
        audioBuffer: [Float],
        language: String = "auto",
        config: DecodeConfig
    ) throws -> DecodeResult {
        guard !audioBuffer.isEmpty else {
            throw WhisperError.emptyAudioBuffer
        }

        var capturedError: WhisperError?
        let result = TemperatureFallback.run(config: config) { temperature in
            PipelineEventLog.shared.append(
                "🎛️ decoder.attempt temperature=\(temperature)",
                kind: .info
            )
            do {
                let attempt = try runDecode(
                    audioBuffer: audioBuffer,
                    language: language,
                    temperature: temperature,
                    config: config
                )
                let ratio = DecodeQuality.compressionRatio(of: attempt.text)
                let accepted = DecodeQuality.isAcceptable(
                    compressionRatio: ratio,
                    avgLogprob: attempt.avgLogprob,
                    config: config
                )
                PipelineEventLog.shared.append(
                    "📊 decoder.attempt_result compression=\(String(format: "%.2f", ratio)) avg_logprob=\(String(format: "%.2f", attempt.avgLogprob)) accepted=\(accepted)",
                    kind: accepted ? .success : .info
                )
                return attempt
            } catch let error as WhisperError {
                capturedError = error
                // Surface as a maximally-bad attempt so the ladder moves on;
                // the captured error is re-thrown if every attempt failed.
                return DecodeAttempt(text: "", temperature: temperature, avgLogprob: -.greatestFiniteMagnitude)
            } catch {
                capturedError = .transcriptionFailed(reason: error.localizedDescription)
                return DecodeAttempt(text: "", temperature: temperature, avgLogprob: -.greatestFiniteMagnitude)
            }
        }

        // Every attempt threw and produced no usable text.
        if result.text.isEmpty, let capturedError, result.fallbackExhausted {
            throw capturedError
        }

        if result.fallbackExhausted {
            PipelineEventLog.shared.append("🚧 decoder.fallback_exhausted", kind: .error)
        }
        return result
    }

    /// Performs a single Whisper decode at a specific temperature and returns
    /// the concatenated text plus the average per-token log probability.
    private func runDecode(
        audioBuffer: [Float],
        language: String,
        temperature: Float,
        config: DecodeConfig
    ) throws -> DecodeAttempt {
        // Temperature 0 uses beam search (most robust around pauses and
        // disfluencies on small models); higher temperatures use sampling,
        // matching upstream Whisper's fallback behaviour.
        let useBeam = temperature == 0
        var params = whisper_full_default_params(
            useBeam ? WHISPER_SAMPLING_BEAM_SEARCH : WHISPER_SAMPLING_GREEDY
        )
        if useBeam {
            params.beam_search.beam_size = Int32(config.beamSize)
        }
        params.temperature = temperature
        // Disable whisper.cpp's internal fallback loop — we drive the ladder
        // explicitly so we can read each attempt's confidence signals.
        params.temperature_inc = 0

        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.single_segment = false
        params.no_timestamps = true
        params.n_threads = max(1, Int32(ProcessInfo.processInfo.activeProcessorCount - 1))

        // Confidence-driven fallback thresholds (mirroring OpenAI defaults).
        params.entropy_thold = config.compressionRatioThreshold
        params.logprob_thold = config.logprobThreshold

        // Robustness tweaks for pause-heavy recordings (see PRD-0001/0003):
        //  * `no_speech_thold` kept high so a chunk's internal pause doesn't
        //    cause Whisper to discard the whole window's real speech.
        //  * `suppress_blank = false` lets a chunk that opens with a brief
        //    quiet section (typical right after a pause) still emit tokens.
        params.no_speech_thold = config.noSpeechThreshold
        params.suppress_blank = false

        // Cross-chunk continuity: feed the previous confident chunk's tail as
        // the initial prompt when conditioning is enabled and a prompt exists.
        let hasPrompt = config.conditionOnPreviousText && !config.initialPrompt.isEmpty
        params.no_context = !hasPrompt

        let cLanguage = strdup(language)
        defer { free(cLanguage) }
        params.language = UnsafePointer(cLanguage)
        // `detect_language = true` is whisper.cpp's *detect-only* mode: it
        // identifies the language and returns without transcribing. Auto-detect
        // during normal decoding is requested via `language = "auto"` alone, so
        // this flag must stay false or every "auto" decode yields empty text.
        params.detect_language = false

        let cPrompt: UnsafeMutablePointer<CChar>? = hasPrompt ? strdup(config.initialPrompt) : nil
        defer { if let cPrompt { free(cPrompt) } }
        if let cPrompt {
            params.initial_prompt = UnsafePointer(cPrompt)
            PipelineEventLog.shared.append(
                "🧵 decoder.prompt_passed chars=\(config.initialPrompt.count)",
                kind: .info
            )
        }

        let result = audioBuffer.withUnsafeBufferPointer { bufferPtr in
            whisper_full(context, params, bufferPtr.baseAddress, Int32(audioBuffer.count))
        }
        guard result == 0 else {
            throw WhisperError.transcriptionFailed(reason: "whisper_full returned error code \(result)")
        }

        let segmentCount = whisper_full_n_segments(context)
        var text = ""
        var logprobSum: Double = 0
        var tokenCount = 0
        for segment in 0..<segmentCount {
            if let cStr = whisper_full_get_segment_text(context, segment) {
                text += String(cString: cStr)
            }
            let tokens = whisper_full_n_tokens(context, segment)
            for token in 0..<tokens {
                let data = whisper_full_get_token_data(context, segment, token)
                logprobSum += Double(data.plog)
                tokenCount += 1
            }
        }

        let avgLogprob = tokenCount > 0 ? Float(logprobSum / Double(tokenCount)) : 0
        return DecodeAttempt(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            temperature: temperature,
            avgLogprob: avgLogprob
        )
    }
}

