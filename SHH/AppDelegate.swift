import AppKit
import AVFoundation
import Combine
import SwiftData

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var recordingCoordinator: RecordingCoordinator?
    private var overlayController: OverlayWidgetController?
    private var stylePickerController: StylePickerController?
    private let overlayViewModel = OverlayViewModel()
    private let stylePickerViewModel = StylePickerViewModel()
    private var audioLevelCancellable: AnyCancellable?
    var modelContainer: ModelContainer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.applicationIconImage = makeAppIcon()

        // Request microphone access early so the system dialog appears immediately
        // rather than silently capturing silence the first time the user records.
        AVAudioApplication.requestRecordPermission { _ in }

        setupRecordingCoordinator()
        setupOverlayWidget()
        wireStylePicker()

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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        NotificationCenter.default.post(name: .openDashboardWindow, object: nil)
        return true
    }

    // MARK: - App Icon

    private func makeAppIcon() -> NSImage {
        let canvasSize = CGSize(width: 512, height: 512)
        let bgColor = NSColor(red: 233 / 255.0, green: 79 / 255.0, blue: 55 / 255.0, alpha: 1.0)
        let fgColor = NSColor(red: 246 / 255.0, green: 247 / 255.0, blue: 235 / 255.0, alpha: 1.0)

        return NSImage(size: canvasSize, flipped: false) { rect in
            bgColor.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 115, yRadius: 115).fill()

            let config = NSImage.SymbolConfiguration(paletteColors: [fgColor])
            guard let symbol = NSImage(systemSymbolName: "waveform", accessibilityDescription: nil)?
                .withSymbolConfiguration(config) else { return true }

            let targetHeight = canvasSize.height * 0.42
            let scale = targetHeight / symbol.size.height
            let scaledWidth = symbol.size.width * scale
            let drawRect = NSRect(
                x: (canvasSize.width - scaledWidth) / 2,
                y: (canvasSize.height - targetHeight) / 2,
                width: scaledWidth,
                height: targetHeight
            )
            symbol.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }
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
            let nowRecording = audioCapture.isRecording
            DispatchQueue.main.async {
                vm.isRecording = nowRecording
            }
        }
        let originalOnStop = coordinator.stateMachine.onRecordingDidStop
        coordinator.stateMachine.onRecordingDidStop = { mode in
            originalOnStop?(mode)
            DispatchQueue.main.async {
                vm.isRecording = false
            }
        }
        coordinator.stateMachine.onForcedIdle = {
            DispatchQueue.main.async {
                vm.isRecording = false
            }
        }
        let originalOnCancel = coordinator.stateMachine.onRecordingDidCancel
        coordinator.stateMachine.onRecordingDidCancel = {
            originalOnCancel?()
            DispatchQueue.main.async {
                vm.isRecording = false
            }
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
        let pickerController = StylePickerController(viewModel: stylePickerViewModel)

        controller.show()
        overlayController = controller
        stylePickerController = pickerController
    }

    /// Wire the style picker to the recording state machine and widget tap.
    /// Called after both setupRecordingCoordinator() and setupOverlayWidget().
    private func wireStylePicker() {
        guard let coordinator = recordingCoordinator,
              let widgetController = overlayController,
              let pickerController = stylePickerController else { return }

        // Wire style selection to persist to SwiftData
        let container = modelContainer
        let pickerVM = stylePickerViewModel
        stylePickerViewModel.onStyleSelected = { selectedId in
            guard let container else { return }
            let context = ModelContext(container)
            let descriptor = FetchDescriptor<Style>()
            guard let allStyles = try? context.fetch(descriptor) else { return }
            for style in allStyles {
                style.isActive = (style.id == selectedId)
            }
            try? context.save()
        }

        // Show/hide picker with recording
        let vm = overlayViewModel
        nonisolated(unsafe) let audioCapture = coordinator.audioCaptureManager
        let pickerCtrl = pickerController
        let widgetCtrl = widgetController

        let previousOnStart = coordinator.stateMachine.onRecordingDidStart
        coordinator.stateMachine.onRecordingDidStart = {
            previousOnStart?()
            let nowRecording = audioCapture.isRecording
            DispatchQueue.main.async {
                vm.isRecording = nowRecording
                if nowRecording {
                    if let container {
                        let context = ModelContext(container)
                        pickerVM.reload(from: context)
                    }
                    let widgetFrame = widgetCtrl.panelWindow.frame
                    pickerCtrl.show(relativeTo: widgetFrame)
                }
            }
        }

        let previousOnStop = coordinator.stateMachine.onRecordingDidStop
        coordinator.stateMachine.onRecordingDidStop = { mode in
            previousOnStop?(mode)
            DispatchQueue.main.async {
                vm.isRecording = false
                pickerCtrl.hide()
            }
        }

        coordinator.stateMachine.onForcedIdle = {
            DispatchQueue.main.async {
                vm.isRecording = false
                pickerCtrl.hide()
            }
        }

        let previousOnCancel = coordinator.stateMachine.onRecordingDidCancel
        coordinator.stateMachine.onRecordingDidCancel = {
            previousOnCancel?()
            DispatchQueue.main.async {
                vm.isRecording = false
                pickerCtrl.hide()
            }
        }

        // Widget tap toggles recording + picker
        nonisolated(unsafe) let coordRef = coordinator
        overlayViewModel.onWidgetTapped = {
            if coordRef.stateMachine.state == .idle {
                coordRef.startLockIn()
            } else {
                coordRef.stopCurrentRecording()
                pickerCtrl.hide()
            }
        }
    }
}

extension Notification.Name {
    static let shhTranscriptionDidComplete = Notification.Name("shhTranscriptionDidComplete")
    static let shhRecordingError = Notification.Name("shhRecordingError")
    static let openDashboardWindow = Notification.Name("openDashboardWindow")
}
