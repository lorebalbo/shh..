import SwiftUI

/// An animated sound-wave visualisation that reacts to real-time audio levels.
/// Renders multiple vertical bars that oscillate based on the audio level value.
struct WaveformView: View {
    let audioLevel: Float
    let barCount: Int = 5

    @State private var phase: Double = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            HStack(spacing: 2) {
                ForEach(0..<barCount, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(.red)
                        .frame(width: 3, height: barHeight(for: index, date: timeline.date))
                }
            }
        }
    }

    private func barHeight(for index: Int, date: Date) -> CGFloat {
        let time = date.timeIntervalSinceReferenceDate
        let offset = Double(index) * 0.6
        let wave = sin(time * 6.0 + offset) * 0.5 + 0.5
        let level = CGFloat(max(audioLevel, 0.05))
        let height = 4.0 + level * 20.0 * wave
        return min(max(height, 4), 28)
    }
}
