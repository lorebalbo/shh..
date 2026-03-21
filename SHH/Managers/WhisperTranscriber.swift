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
        guard !audioBuffer.isEmpty else {
            throw WhisperError.emptyAudioBuffer
        }

        var params = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
        params.print_realtime = false
        params.print_progress = false
        params.print_timestamps = false
        params.print_special = false
        params.single_segment = false
        params.no_timestamps = true
        params.n_threads = max(1, Int32(ProcessInfo.processInfo.activeProcessorCount - 1))

        if language == "auto" {
            params.detect_language = true
        } else {
            params.detect_language = false
        }

        let cLanguage = strdup(language)
        defer { free(cLanguage) }
        params.language = UnsafePointer(cLanguage)
        
        let result = audioBuffer.withUnsafeBufferPointer { bufferPtr in
            whisper_full(context, params, bufferPtr.baseAddress, Int32(audioBuffer.count))
        }

        guard result == 0 else {
            throw WhisperError.transcriptionFailed(reason: "whisper_full returned error code \(result)")
        }

        let segmentCount = whisper_full_n_segments(context)
        var transcribedText = ""

        for i in 0..<segmentCount {
            if let cStr = whisper_full_get_segment_text(context, i) {
                transcribedText += String(cString: cStr)
            }
        }

        return transcribedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
