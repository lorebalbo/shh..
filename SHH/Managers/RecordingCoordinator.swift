@preconcurrency import AVFoundation
import Foundation
import OSLog
import SwiftData

/// Coordinates the recording lifecycle by wiring GlobalInputManager events
/// to RecordingStateMachine transitions, and connecting those transitions
/// to AudioCaptureManager and TranscriptionPipeline.
///
/// On recording start, AudioCaptureManager begins capturing. On recording stop,
/// the captured audio is dispatched to TranscriptionPipeline on a background
/// queue. After transcription, the RAW text flows through TextProcessingPipeline
/// for Style-based LLM processing, and the result is persisted to SwiftData.
/// On pipeline completion, `onTranscriptionComplete` fires on the main thread.
final class RecordingCoordinator {
    let inputManager = GlobalInputManager()
    let stateMachine = RecordingStateMachine()
    let audioCaptureManager: AudioCaptureManager
    let transcriptionPipeline: TranscriptionPipeline
    let textProcessingPipeline: TextProcessingPipeline?
    let clipboardManager: ClipboardManager
    private let modelContext: ModelContext?
    private let logger = Logger(subsystem: "com.shh", category: "pipeline")

    /// Fires on the main thread when transcription completes.
    /// Parameters: final text (processed or raw), recording mode that produced it.
    var onTranscriptionComplete: ((String, RecordingMode) -> Void)?

    /// Fires on the main thread when an error occurs during recording or transcription.
    var onError: ((Error) -> Void)?

    private let processingQueue = DispatchQueue(
        label: "com.shh.transcription-processing",
        qos: .userInitiated
    )

    init(
        audioCaptureManager: AudioCaptureManager = AudioCaptureManager(),
        transcriptionPipeline: TranscriptionPipeline,
        textProcessingPipeline: TextProcessingPipeline? = nil,
        clipboardManager: ClipboardManager = ClipboardManager(),
        modelContext: ModelContext? = nil
    ) {
        self.audioCaptureManager = audioCaptureManager
        self.transcriptionPipeline = transcriptionPipeline
        self.textProcessingPipeline = textProcessingPipeline
        self.clipboardManager = clipboardManager
        self.modelContext = modelContext
        setupBindings()
    }

    /// Starts the global input manager. Returns `false` if Accessibility
    /// permission is not granted or the CGEvent Tap cannot be installed.
    @discardableResult
    func start() -> Bool {
        inputManager.start()
    }

    /// Stops the global input manager.
    func stop() {
        inputManager.stop()
    }

    /// Enters lock-in recording mode directly (e.g., from overlay widget tap).
    func startLockIn() {
        stateMachine.startLockIn()
    }

    /// Stops recording regardless of the current mode.
    /// Uses the natural state-machine transitions so the transcription pipeline fires normally.
    func stopCurrentRecording() {
        switch stateMachine.state {
        case .lockInActive, .continuousActive:
            stateMachine.handleFnPress()
        case .pushToTalkActive:
            stateMachine.handleFnRelease()
        case .idle:
            break
        }
    }

    // MARK: - Private

    private func setupBindings() {
        // Wire input events → state machine
        inputManager.onFnPress = { [weak self] in
            self?.stateMachine.handleFnPress() ?? false
        }
        inputManager.onFnRelease = { [weak self] in
            self?.stateMachine.handleFnRelease() ?? false
        }
        inputManager.onSpacePress = { [weak self] in
            self?.stateMachine.handleSpacePress() ?? false
        }
        inputManager.onEscPress = { [weak self] in
            self?.stateMachine.handleEscPress() ?? false
        }

        // Wire state machine → audio capture + transcription pipeline
        stateMachine.onRecordingDidStart = { [weak self] in
            guard let self else { return }
            do {
                try self.audioCaptureManager.startRecording()
                self.logger.info("Audio capture started")
                PipelineEventLog.shared.append("🎙️ Recording started")
            } catch {
                self.logger.error("Audio capture failed to start: \(error.localizedDescription)")
                PipelineEventLog.shared.append("❌ Recording failed to start: \(error.localizedDescription)", kind: .error)
                self.stateMachine.forceIdle()
                self.onError?(error)
            }
        }

        stateMachine.onRecordingDidStop = { [weak self] mode in
            guard let self else { return }
            let audioBuffer = self.audioCaptureManager.stopRecording()
            let duration = String(format: "%.1f", Double(audioBuffer.count) / 16_000.0)
            self.logger.info("Recording stopped: \(audioBuffer.count) samples (\(duration)s)")
            PipelineEventLog.shared.append("⏹ Stopped — \(audioBuffer.count) samples (\(duration)s)")

            guard !audioBuffer.isEmpty else {
                self.logger.warning("Audio buffer is empty — check microphone permission")
                PipelineEventLog.shared.append("⚠️ No audio captured — check microphone permission", kind: .error)
                return
            }

            PipelineEventLog.shared.append("🔄 Transcribing…")
            self.processTranscription(audioBuffer: audioBuffer, mode: mode)
        }

        stateMachine.onRecordingDidCancel = { [weak self] in
            guard let self else { return }
            _ = self.audioCaptureManager.stopRecording()
            self.logger.info("Recording cancelled")
            PipelineEventLog.shared.append("🚫 Recording cancelled")
        }

        // Handle audio interruptions (e.g. microphone disconnect mid-recording)
        audioCaptureManager.onInterruption = { [weak self] audioBuffer, _ in
            guard let self else { return }

            let mode: RecordingMode
            switch self.stateMachine.state {
            case .pushToTalkActive: mode = .pushToTalk
            case .continuousActive: mode = .continuous
            case .lockInActive: mode = .lockIn
            case .idle: return
            }

            self.stateMachine.forceIdle()

            guard !audioBuffer.isEmpty else { return }

            self.processTranscription(audioBuffer: audioBuffer, mode: mode)
        }
    }

    private func processTranscription(audioBuffer: [Float], mode: RecordingMode) {
        nonisolated(unsafe) let pipeline = self.transcriptionPipeline
        // Read the user's language preference at call time (UserDefaults is thread-safe for reads)
        let language = UserDefaults.standard.string(forKey: "transcriptionLanguage") ?? "auto"

        processingQueue.async { [weak self] in
            let audioFilePath: String? = nil

            // Log peak amplitude so we can see if the mic level is adequate
            let peak = audioBuffer.reduce(Float(0)) { max($0, abs($1)) }
            let rms = sqrt(audioBuffer.reduce(Float(0)) { $0 + $1 * $1 } / Float(audioBuffer.count))
            PipelineEventLog.shared.append(
                String(format: "📊 Audio peak=%.4f rms=%.4f lang=%@", peak, rms, language)
            )

            do {
                let rawText = try pipeline.transcribe(audioBuffer: audioBuffer, language: language)

                self?.logger.info("Transcription (\(rawText.count) chars): \"\(rawText.prefix(120))\"")
                PipelineEventLog.shared.append(
                    rawText.isEmpty ? "⚠️ No speech detected in audio" : "🔤 Transcribed: \"\(rawText.prefix(80))\"",
                    kind: rawText.isEmpty ? .error : .success
                )

                guard let self else { return }

                if rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // No speech — still persist so user can play the audio back
                    let result = TextProcessingResult(rawText: "(no speech detected)", processedText: nil, styleId: nil)
                    DispatchQueue.main.async { self.persistDictationEntry(result: result, audioFilePath: audioFilePath) }
                    return
                }

                // Run text through LLM processing pipeline (if available)
                if let textPipeline = self.textProcessingPipeline {
                    nonisolated(unsafe) let capturedSelf = self
                    nonisolated(unsafe) let capturedPipeline = textPipeline
                    Task { @MainActor in
                        let result = await capturedPipeline.process(rawText: rawText)
                        let finalText = result.processedText ?? result.rawText

                        capturedSelf.persistDictationEntry(result: result, audioFilePath: audioFilePath)
                        capturedSelf.clipboardManager.autoPaste(text: finalText)
                        capturedSelf.onTranscriptionComplete?(finalText, mode)
                    }
                } else {
                    // No LLM pipeline — persist raw entry directly
                    let result = TextProcessingResult(rawText: rawText, processedText: nil, styleId: nil)
                    DispatchQueue.main.async {
                        self.persistDictationEntry(result: result, audioFilePath: audioFilePath)
                        self.clipboardManager.autoPaste(text: rawText)
                        self.onTranscriptionComplete?(rawText, mode)
                    }
                }
            } catch {
                self?.logger.error("Transcription error: \(error.localizedDescription)")
                PipelineEventLog.shared.append("❌ Transcription error: \(error.localizedDescription)", kind: .error)
                if let self {
                    let result = TextProcessingResult(rawText: "(transcription error)", processedText: nil, styleId: nil)
                    DispatchQueue.main.async {
                        self.persistDictationEntry(result: result, audioFilePath: nil)
                        self.onError?(error)
                    }
                } else {
                    DispatchQueue.main.async { self?.onError?(error) }
                }
            }
        }
    }

    private func persistDictationEntry(result: TextProcessingResult, audioFilePath: String? = nil) {
        guard let modelContext else {
            logger.error("Cannot persist entry: modelContext is nil")
            PipelineEventLog.shared.append("❌ Cannot save entry: no database context", kind: .error)
            return
        }

        nonisolated(unsafe) let unsafeContext = modelContext
        DispatchQueue.main.async {
            let entry = DictationEntry(
                rawText: result.rawText,
                processedText: result.processedText,
                styleId: result.styleId,
                audioFilePath: audioFilePath
            )
            unsafeContext.insert(entry)
            do {
                try unsafeContext.save()
                PipelineEventLog.shared.append("💾 Saved to history", kind: .success)
            } catch {
                PipelineEventLog.shared.append("❌ DB save failed: \(error.localizedDescription)", kind: .error)
            }
        }
    }

}
