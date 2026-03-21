import AVFoundation
import ApplicationServices
import AppKit
import Observation

@Observable
@MainActor
final class PermissionManager {
    private(set) var accessibilityGranted = false
    private(set) var microphoneGranted = false

    var allPermissionsGranted: Bool {
        accessibilityGranted && microphoneGranted
    }

    // MARK: - Accessibility

    func checkAccessibilityPermission() {
        accessibilityGranted = AXIsProcessTrusted()
    }

    func requestAccessibilityPermission() {
        let options = [
            "AXTrustedCheckOptionPrompt" as CFString: true as CFBoolean
        ] as CFDictionary
        accessibilityGranted = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Microphone

    func checkMicrophonePermission() {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            microphoneGranted = true
        default:
            microphoneGranted = false
        }
    }

    func requestMicrophonePermission() async {
        microphoneGranted = await AVCaptureDevice.requestAccess(for: .audio)
    }

    // MARK: - System Settings

    func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func openMicrophoneSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Polls both permission states. Call periodically (e.g. when the app
    /// becomes active) so the UI refreshes after the user grants access
    /// in System Settings.
    func refreshPermissions() {
        checkAccessibilityPermission()
        checkMicrophonePermission()
    }
}
