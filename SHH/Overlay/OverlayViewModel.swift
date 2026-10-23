import Combine
import Foundation

/// Observable view model that exposes the recording state and audio level
/// to the overlay widget's SwiftUI views.
/// Conforms to @unchecked Sendable because all mutations happen on the main
/// thread (via DispatchQueue.main or MainActor), but Swift 6 cannot prove this statically.
final class OverlayViewModel: ObservableObject, @unchecked Sendable {

    @Published var isRecording: Bool = false
    /// Recordings still being transcribed or styled.
    @Published var processingCount: Int = 0
    @Published var audioLevel: Float = 0.0
    @Published var tapScale: CGFloat = 1.0

    var isProcessing: Bool { processingCount > 0 }

    /// The "2 processing" label shown against the widget, or nil to hide it.
    var queueLabel: String? {
        Self.queueLabel(processingCount: processingCount, isRecording: isRecording)
    }

    /// Called when the user taps the overlay widget while idle.
    var onWidgetTapped: (() -> Void)?

    /// A lone recording processing just shows the widget's spinner. Once recordings
    /// queue up — recording over one in flight, or several in flight — the label
    /// counts them.
    static func queueLabel(processingCount: Int, isRecording: Bool) -> String? {
        guard processingCount > 1 || (processingCount == 1 && isRecording) else { return nil }
        return "\(processingCount) processing"
    }
}
