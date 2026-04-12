import Foundation

enum TranscriptionPipelineError: Error, LocalizedError {
    case noModelAvailable
    case modelLoadFailed(underlying: WhisperError)
    case transcriptionFailed(underlying: WhisperError)
    case audioCaptureFailed(underlying: AudioCaptureError)
    case noAudioCaptured

    var errorDescription: String? {
        switch self {
        case .noModelAvailable:
            return "No transcription model is available. Please ensure the base model is bundled or download a model."
        case .modelLoadFailed(let err):
            return "Failed to load transcription model: \(err.localizedDescription)"
        case .transcriptionFailed(let err):
            return "Transcription failed: \(err.localizedDescription)"
        case .audioCaptureFailed(let err):
            return "Audio capture failed: \(err.localizedDescription)"
        case .noAudioCaptured:
            return "No audio was captured during the recording"
        }
    }
}

/// Orchestrates the transcription flow: accepts a recorded audio buffer from
/// AudioCaptureManager, passes it to WhisperTranscriber with the active model
/// and language preference, and returns the resulting RAW text.
final class TranscriptionPipeline {
    private let modelManager: ModelManager
    private var transcriber: WhisperTranscriber?
    private var loadedModelPath: String?

    init(modelManager: ModelManager = .shared) {
        self.modelManager = modelManager
    }

    /// Transcribes audio samples into raw text using the active whisper model.
    /// - Parameters:
    ///   - audioBuffer: PCM audio samples at 16kHz, mono, Float32.
    ///   - language: ISO 639-1 language code (e.g. "en"), or "auto" for auto-detection.
    /// - Returns: The transcribed raw text string.
    func transcribe(audioBuffer: [Float], language: String = "auto") throws -> String {
        guard !audioBuffer.isEmpty else {
            return ""
        }

        let transcriber = try resolveTranscriber()

        do {
            return try transcriber.transcribe(
                audioBuffer: normalizeAudio(audioBuffer),
                language: language
            )
        } catch let error as WhisperError {
            throw TranscriptionPipelineError.transcriptionFailed(underlying: error)
        }
    }

    /// Normalizes a Float32 audio buffer to a peak of ~0.95 so Whisper receives
    /// clean, in-range samples. Handles both clipped (peak > 1.0) and quiet input.
    private func normalizeAudio(_ samples: [Float]) -> [Float] {
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        // Below noise floor — amplifying would only boost noise, not speech.
        guard peak > 0.001 else { return samples }
        // Always scale: attenuates clipped audio (peak > 1.0) AND amplifies quiet audio.
        // Cap amplification at 10× to avoid over-amplifying borderline-silent buffers.
        let scale = min(0.95 / peak, 10.0)
        return samples.map { $0 * scale }
    }

    /// Captures the model path at the moment of invocation to ensure model
    /// switches during inference don't affect the in-progress transcription.
    private func resolveTranscriber() throws -> WhisperTranscriber {
        guard let modelPath = modelManager.resolveActiveModelPath() else {
            throw TranscriptionPipelineError.noModelAvailable
        }

        // Reuse existing transcriber if model hasn't changed
        if let existing = transcriber, loadedModelPath == modelPath {
            return existing
        }

        do {
            let newTranscriber = try WhisperTranscriber(modelPath: modelPath)
            transcriber = newTranscriber
            loadedModelPath = modelPath
            return newTranscriber
        } catch let error as WhisperError {
            throw TranscriptionPipelineError.modelLoadFailed(underlying: error)
        }
    }

    /// Invalidates the cached transcriber so the next transcription
    /// picks up a newly-selected model.
    func invalidateCachedModel() {
        transcriber = nil
        loadedModelPath = nil
    }

    /// Releases the whisper context immediately so ggml-metal resources are
    /// torn down before the C++ static destructors run during `exit()`.
    func shutdown() {
        transcriber = nil
        loadedModelPath = nil
    }
}
