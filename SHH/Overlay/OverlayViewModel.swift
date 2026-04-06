import Combine
import Foundation

/// Observable view model that exposes the recording state and audio level
/// to the overlay widget's SwiftUI views.
/// Conforms to @unchecked Sendable because all mutations happen on the main
/// thread (via DispatchQueue.main or MainActor), but Swift 6 cannot prove this statically.
final class OverlayViewModel: ObservableObject, @unchecked Sendable {

    @Published var isRecording: Bool = false
    @Published var isProcessing: Bool = false
    @Published var audioLevel: Float = 0.0
    @Published var tapScale: CGFloat = 1.0

    /// Called when the user taps the overlay widget while idle.
    var onWidgetTapped: (() -> Void)?
}
