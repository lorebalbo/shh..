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
    private var vadProcessor: VADProcessor?
    private var loadedVADModelPath: String?

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

        let normalized = TranscriptionEngine.normalize(audioBuffer)
        let vad = resolveVAD()
        if vad == nil {
            PipelineEventLog.shared.append("⚠️ vad.unavailable — no VAD model bundled", kind: .error)
        }

        let transcriber = try resolveTranscriber()

        do {
            return try TranscriptionEngine.run(
                normalizedBuffer: normalized,
                transcriber: transcriber,
                vad: vad,
                language: language,
                decodeConfig: .default
            )
        } catch let error as WhisperError {
            throw TranscriptionPipelineError.transcriptionFailed(underlying: error)
        }
    }

    /// Lazily resolves a VADProcessor bound to the bundled Silero model.
    /// Returns nil only when the model cannot be located.
    private func resolveVAD() -> VADProcessor? {
        guard let vadModelPath = modelManager.resolveVADModelPath() else { return nil }
        if let existing = vadProcessor, loadedVADModelPath == vadModelPath {
            return existing
        }
        let processor = VADProcessor(modelPath: vadModelPath)
        vadProcessor = processor
        loadedVADModelPath = vadModelPath
        return processor
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
        vadProcessor = nil
        loadedVADModelPath = nil
    }
}
