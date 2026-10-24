import AppKit
import AVFoundation
import Combine
import SwiftData
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var recordingCoordinator: RecordingCoordinator?
    private var overlayController: OverlayWidgetController?
    private var stylePickerController: StylePickerController?
    private let overlayViewModel = OverlayViewModel()
    private let stylePickerViewModel = StylePickerViewModel()
    private var audioLevelCancellable: AnyCancellable?
    private var styleChangeObserver: NSObjectProtocol?
    var modelContainer: ModelContainer?

    // Dashboard window managed directly via AppKit for reliable lifecycle control.
    private var dashboardWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.applicationIconImage = makeAppIcon()
        Ink.registerFonts()

        // Request microphone access early so the system dialog appears immediately
        // rather than silently capturing silence the first time the user records.
        AVAudioApplication.requestRecordPermission { _ in }

        setupRecordingCoordinator()
        setupOverlayWidget()
        wireStylePicker()
        observeStyleChanges()

        // Build the dashboard window. PermissionManager is @MainActor so it must
        // be created here (applicationDidFinishLaunching is @MainActor via the
        // NSApplicationDelegate protocol).
        if let container = modelContainer {
            let permissionManager = PermissionManager()
            let rootView = DashboardView()
                .environment(permissionManager)
                .modelContainer(container)

            // Ink: one paper surface edge to edge, with the traffic lights over the ink sidebar.
            // Follows the system appearance: Paper in light mode, its negative in dark mode.
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 800, height: 550),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.contentView = NSHostingView(rootView: rootView)
            window.center()
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 700, height: 500)
            window.title = "Shh.."
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.backgroundColor = Ink.windowBackground
            dashboardWindow = window
        }

        // Open the dashboard immediately when any permission is missing.
        if !allPermissionsGranted {
            showDashboard()
        }

        // Retry installing the CGEvent tap whenever the app becomes active.
        // This handles the common case where Accessibility permission is granted
        // after the app has already launched (initial launch without permission).
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(retryEventTapIfNeeded),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenDashboard),
            name: .openDashboardWindow,
            object: nil
        )
    }

    @objc private func retryEventTapIfNeeded() {
        // Show the overlay widget as soon as all permissions have been granted.
        if allPermissionsGranted {
            overlayController?.show()
        }
        guard let coordinator = recordingCoordinator,
              !coordinator.inputManager.isRunning else { return }
        coordinator.start()
    }

    @objc private func handleOpenDashboard() {
        showDashboard()
    }

    private func observeStyleChanges() {
        styleChangeObserver = NotificationCenter.default.addObserver(
            forName: .shhStylesDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.reloadStylePickerFromStore()
        }
    }

    private func reloadStylePickerFromStore() {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        stylePickerViewModel.reload(from: context)

        guard let pickerController = stylePickerController,
              pickerController.isVisible,
              let overlayController = overlayController else { return }

        pickerController.updatePosition(relativeTo: overlayController.anchorFrame)
    }

    /// Returns true when every permission required by the app has been granted.
    private var allPermissionsGranted: Bool {
        AXIsProcessTrusted()
            && AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let styleChangeObserver {
            NotificationCenter.default.removeObserver(styleChangeObserver)
        }
        recordingCoordinator?.shutdown()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showDashboard()
        return true
    }

    func showDashboard() {
        dashboardWindow?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    // MARK: - App Icon

    private func makeAppIcon() -> NSImage {
        // 1024×1024 canvas per Apple HIG for macOS Big Sur+ icons.
        let canvasSize = CGSize(width: 1024, height: 1024)
        // Paper, lit: white at the lit corner to a warm grey; the mark in the dashboard's ink.
        let paper = [
            NSColor(srgbRed: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
            NSColor(srgbRed: 246 / 255.0, green: 245 / 255.0, blue: 242 / 255.0, alpha: 1.0),
            NSColor(srgbRed: 228 / 255.0, green: 226 / 255.0, blue: 221 / 255.0, alpha: 1.0),
        ]
        let fgColor = NSColor(srgbRed: 13 / 255.0, green: 13 / 255.0, blue: 13 / 255.0, alpha: 1.0)

        return NSImage(size: canvasSize, flipped: false) { rect in
            // Apple icon grid: squircle inset ~100pt from each edge → 824×824 shape.
            let iconInset: CGFloat = 100
            let iconRect = rect.insetBy(dx: iconInset, dy: iconInset)
            let cornerRadius: CGFloat = 185

            let squircle = NSBezierPath(roundedRect: iconRect, xRadius: cornerRadius, yRadius: cornerRadius)

            // A soft shadow under the squircle, as in Apple's icon template, so the white
            // shape keeps its edge on light backgrounds.
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowOffset = NSSize(width: 0, height: -10)
            shadow.shadowBlurRadius = 24
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
            shadow.set()
            NSColor.white.setFill()
            squircle.fill()
            NSGraphicsContext.restoreGraphicsState()

            // Lit from far beyond the top-right corner: a radial gradient centred
            // outside the shape, lit at the nearest corner, shaded at the farthest.
            let light = NSPoint(x: iconRect.maxX + iconRect.width * 0.35, y: iconRect.maxY + iconRect.height * 0.35)
            NSGraphicsContext.saveGraphicsState()
            squircle.addClip()
            NSGradient(colors: paper, atLocations: [0, 0.5, 1], colorSpace: .sRGB)?.draw(
                fromCenter: light, radius: hypot(light.x - iconRect.maxX, light.y - iconRect.maxY),
                toCenter: light, radius: hypot(light.x - iconRect.minX, light.y - iconRect.minY),
                options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation]
            )
            NSGraphicsContext.restoreGraphicsState()

            guard let mark = NSImage(named: "AppMark"),
                  let context = NSGraphicsContext.current?.cgContext else { return true }

            // Mark at 62% of the icon shape height, matching scripts/generate-icon.swift.
            let targetHeight = iconRect.height * 0.62
            let scaledWidth = mark.size.width * targetHeight / mark.size.height
            let drawRect = NSRect(
                x: iconRect.midX - scaledWidth / 2,
                y: iconRect.midY - targetHeight / 2,
                width: scaledWidth,
                height: targetHeight
            )
            // Tint ink: draw the mark's alpha, then paint the colour through it.
            context.beginTransparencyLayer(auxiliaryInfo: nil)
            mark.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1.0)
            fgColor.setFill()
            drawRect.fill(using: .sourceIn)
            context.endTransparencyLayer()
            return true
        }
    }

    private func setupRecordingCoordinator() {
        let vm = overlayViewModel
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

        // The widget's spinner and "N processing" badge follow the transcription queue.
        coordinator.transcriptionQueue.onPendingCountChange = { count in
            vm.processingCount = count
        }

        coordinator.start()
        recordingCoordinator = coordinator

        // Bind recording state to overlay
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

        // Only show the widget immediately if all permissions are already granted.
        // Otherwise it will be shown by retryEventTapIfNeeded once the user grants
        // the missing permissions and returns to the app.
        if allPermissionsGranted {
            controller.show()
        }
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
            do {
                try context.save()
                NotificationCenter.default.post(name: .shhStylesDidChange, object: nil)
            } catch {
            }
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
                    pickerCtrl.show(relativeTo: widgetCtrl.anchorFrame)
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

        // Keep the picker clear of the "N processing" badge as it comes and goes.
        widgetController.onBadgeChanged = {
            if pickerCtrl.isVisible {
                pickerCtrl.updatePosition(relativeTo: widgetCtrl.anchorFrame)
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
