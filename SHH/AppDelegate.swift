import AppKit
import AVFoundation
import Combine
import SwiftData

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var recordingCoordinator: RecordingCoordinator?
    private var overlayController: OverlayWidgetController?
    private let overlayViewModel = OverlayViewModel()
    private var audioLevelCancellable: AnyCancellable?
    var modelContainer: ModelContainer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Request microphone access early so the system dialog appears immediately
        // rather than silently capturing silence the first time the user records.
        AVAudioApplication.requestRecordPermission { _ in }

        setupRecordingCoordinator()
        setupOverlayWidget()

        // Retry installing the CGEvent tap whenever the app becomes active.
        // This handles the common case where Accessibility permission is granted
        // after the app has already launched (initial launch without permission).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(retryEventTapIfNeeded),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }

    @objc private func retryEventTapIfNeeded() {
        guard let coordinator = recordingCoordinator,
              !coordinator.inputManager.isRunning else { return }
        coordinator.start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func setupRecordingCoordinator() {
        let transcriptionPipeline = TranscriptionPipeline()

        var textProcessingPipeline: TextProcessingPipeline?
        var context: ModelContext?

        if let container = modelContainer {
            let modelContext = ModelContext(container)
            context = modelContext
            textProcessingPipeline = TextProcessingPipeline(modelContext: modelContext)
        }

        let coordinator = RecordingCoordinator(
            transcriptionPipeline: transcriptionPipeline,
            textProcessingPipeline: textProcessingPipeline,
            modelContext: context
        )

        coordinator.onTranscriptionComplete = { text, mode in
            // Auto-paste flow will be implemented in MT-5
            NotificationCenter.default.post(
                name: .shhTranscriptionDidComplete,
                object: nil,
                userInfo: ["text": text, "mode": mode]
            )
        }

        coordinator.onError = { error in
            NotificationCenter.default.post(
                name: .shhRecordingError,
                object: nil,
                userInfo: ["error": error]
            )
        }

        coordinator.start()
        recordingCoordinator = coordinator

        // Bind recording state to overlay
        let vm = overlayViewModel
        let originalOnStart = coordinator.stateMachine.onRecordingDidStart
        // Capture audioCaptureManager with nonisolated(unsafe) — same pattern used
        // throughout this codebase for non-Sendable final classes.
        nonisolated(unsafe) let audioCapture = coordinator.audioCaptureManager
        coordinator.stateMachine.onRecordingDidStart = {
            originalOnStart?()
            // Read the ACTUAL state after the handler runs. If startRecording() threw
            // and forceIdle() was called, audioCapture.isRecording == false here.
            let nowRecording = audioCapture.isRecording
            DispatchQueue.main.async { vm.isRecording = nowRecording }
        }
        let originalOnStop = coordinator.stateMachine.onRecordingDidStop
        coordinator.stateMachine.onRecordingDidStop = { mode in
            originalOnStop?(mode)
            DispatchQueue.main.async { vm.isRecording = false }
        }
        // If recording fails to start (e.g. audio engine error), forceIdle() fires
        // onForcedIdle — clear the recording indicator without any transcription.
        coordinator.stateMachine.onForcedIdle = {
            DispatchQueue.main.async { vm.isRecording = false }
        }

        // Bind audio level to overlay
        audioLevelCancellable = coordinator.audioCaptureManager.audioLevelSubject
            .receive(on: DispatchQueue.main)
            .sink { level in
                vm.audioLevel = level
            }
    }

    private func setupOverlayWidget() {
        let controller = OverlayWidgetController(viewModel: overlayViewModel)

        overlayViewModel.onWidgetTapped = { [weak self] in
            guard let coordinator = self?.recordingCoordinator else { return }
            if coordinator.stateMachine.state == .idle {
                coordinator.startLockIn()
            } else {
                coordinator.stopCurrentRecording()
            }
        }

        controller.show()
        overlayController = controller
    }
}

extension Notification.Name {
    static let shhTranscriptionDidComplete = Notification.Name("shhTranscriptionDidComplete")
    static let shhRecordingError = Notification.Name("shhRecordingError")
}
