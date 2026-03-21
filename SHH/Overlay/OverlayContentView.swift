import SwiftUI

/// The SwiftUI content view hosted inside the overlay NSPanel.
/// Displays either an idle indicator or an active waveform animation
/// based on the current recording state.
struct OverlayContentView: View {
    @ObservedObject var viewModel: OverlayViewModel
    @State private var tapScale: CGFloat = 1.0
    @State private var isDragging = false

    var body: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(
                    Circle()
                        .strokeBorder(
                            viewModel.isRecording ? Color.red.opacity(0.6) : Color.primary.opacity(0.15),
                            lineWidth: 1.5
                        )
                )
                .frame(width: 48, height: 48)

            if viewModel.isRecording {
                WaveformView(audioLevel: viewModel.audioLevel)
                    .transition(.opacity)
            } else {
                Image(systemName: "waveform")
                    .font(.custom("League Spartan", size: 20).weight(.medium))
                    .foregroundStyle(.primary.opacity(0.7))
                    .transition(.opacity)
            }
        }
        .frame(width: 56, height: 56)
        .scaleEffect(tapScale)
        .contentShape(Circle())
        .gesture(
            DragGesture()
                .onChanged { value in
                    isDragging = true
                    viewModel.onDragChanged?(value.translation)
                }
                .onEnded { _ in
                    isDragging = false
                    viewModel.onDragEnded?()
                }
        )
        .onTapGesture {
            guard !isDragging else { return }

            // Visual feedback
            withAnimation(.easeInOut(duration: 0.1)) {
                tapScale = 0.85
            }
            withAnimation(.easeInOut(duration: 0.1).delay(0.1)) {
                tapScale = 1.0
            }

            viewModel.onWidgetTapped?()
        }
        .animation(.easeInOut(duration: 0.25), value: viewModel.isRecording)
    }
}
