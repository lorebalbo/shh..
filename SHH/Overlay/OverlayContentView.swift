import SwiftUI

/// The SwiftUI content view hosted inside the overlay NSPanel.
/// Displays either an idle indicator, an active waveform animation,
/// or a spinning processing indicator based on the current recording state.
/// All mouse interaction (drag & tap) is handled at the NSPanel level
/// via sendEvent(_:) to avoid SwiftUI DragGesture coordinate-space issues.
struct OverlayContentView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @State private var spinAngle: Double = 0

    private var borderColor: Color {
        if viewModel.isRecording { return Color.red.opacity(0.6) }
        if viewModel.isProcessing { return Color.orange.opacity(0.6) }
        return Color.primary.opacity(0.15)
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(borderColor, lineWidth: 1.5)
                )
                .frame(width: 80, height: 16)

            if viewModel.isRecording {
                WaveformView(audioLevel: viewModel.audioLevel)
                    .transition(.opacity)
            } else if viewModel.isProcessing {
                Circle()
                    .trim(from: 0.0, to: 0.75)
                    .stroke(
                        Color.orange.opacity(0.85),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                    )
                    .frame(width: 11, height: 11)
                    .rotationEffect(.degrees(spinAngle))
                    .onAppear {
                        withAnimation(.linear(duration: 0.8).repeatForever(autoreverses: false)) {
                            spinAngle = 360
                        }
                    }
                    .onDisappear { spinAngle = 0 }
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
        .animation(.easeInOut(duration: 0.25), value: viewModel.isProcessing)
    }
}
