import SwiftUI

/// The SwiftUI content view hosted inside the overlay NSPanel.
/// Displays either an idle indicator or an active waveform animation
/// based on the current recording state.
/// All mouse interaction (drag & tap) is handled at the NSPanel level
/// via sendEvent(_:) to avoid SwiftUI DragGesture coordinate-space issues.
struct OverlayContentView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(
                            viewModel.isRecording ? Color.red.opacity(0.6) : Color.primary.opacity(0.15),
                            lineWidth: 1.5
                        )
                )
                .frame(width: 80, height: 16)

            if viewModel.isRecording {
                WaveformView(audioLevel: viewModel.audioLevel)
                    .transition(.opacity)
            } else {
                Image(systemName: "waveform")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary.opacity(0.7))
                    .transition(.opacity)
            }
        }
        .frame(width: 88, height: 22)
        .scaleEffect(viewModel.tapScale)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isRecording)
    }
}
