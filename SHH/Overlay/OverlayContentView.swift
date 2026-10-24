import SwiftUI

/// The SwiftUI content view hosted inside the overlay NSPanel: a see-through ink pill
/// with bars standing still while idle, bars
/// bouncing with the voice while recording, and three dots pulsing while processing.
/// All mouse interaction (drag & tap) is handled at the NSPanel level
/// via sendEvent(_:) to avoid SwiftUI DragGesture coordinate-space issues.
struct OverlayContentView: View {
    @ObservedObject var viewModel: OverlayViewModel

    var body: some View {
        ZStack {
            Capsule()
                .inkGlass()
                .frame(width: 80, height: 16)

            Group {
                if viewModel.isRecording {
                    WaveformView(audioLevel: viewModel.audioLevel)
                } else if viewModel.isProcessing {
                    PulsingDots()
                } else {
                    WaveformView(audioLevel: nil)
                }
            }
            .foregroundStyle(Ink.onInk)
            .transition(.scale(scale: 0.6).combined(with: .opacity))
        }
        .frame(width: 88, height: 22)
        .scaleEffect(viewModel.tapScale)
        // Overshoots a little, like a drop settling (the dashboard's --squish).
        .animation(.timingCurve(0.3, 1.45, 0.5, 1, duration: 0.3), value: viewModel.isRecording)
        .animation(.timingCurve(0.3, 1.45, 0.5, 1, duration: 0.3), value: viewModel.isProcessing)
    }
}

/// Three dots swelling in turn, with the pulse of the dashboard's loading drops.
private struct PulsingDots: View {
    var body: some View {
        TimelineView(.animation) { context in
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    let drip = InkDrops.drip(at: context.date, index: index)
                    Circle()
                        .frame(width: 5, height: 5)
                        .scaleEffect(0.7 + 0.3 * drip)
                        .opacity(0.35 + 0.65 * drip)
                }
            }
        }
    }
}

extension Shape {
    /// The overlay's see-through ink, for the widget and its style picker: a wash of the
    /// dashboard's ink over frosted glass. The blur keeps what's drawn on it readable over
    /// text; the ink tint is what gives it its colour.
    func inkGlass() -> some View {
        fill(Ink.ink.opacity(0.5)).background(.ultraThinMaterial, in: self)
    }
}
