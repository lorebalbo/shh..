import SwiftUI

/// Five round-capped bars in the foreground style. Live, they bounce with the
/// real-time audio level; without a level they stand still in a waveform silhouette.
struct WaveformView: View {
    /// 0–1, or nil for the bars at rest.
    let audioLevel: Float?

    private static let restHeights: [CGFloat] = [4, 7, 10, 7, 4]
    /// The middle bars reach higher, so a loud voice still reads as a wave.
    private static let reach: [CGFloat] = [0.6, 0.85, 1, 0.85, 0.6]
    private static let minHeight: CGFloat = 3
    private static let maxHeight: CGFloat = 11

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: audioLevel == nil)) { timeline in
            HStack(spacing: 2.5) {
                ForEach(0..<Self.restHeights.count, id: \.self) { index in
                    Capsule()
                        .frame(width: 3, height: barHeight(for: index, date: timeline.date))
                }
            }
        }
    }

    private func barHeight(for index: Int, date: Date) -> CGFloat {
        guard let audioLevel else { return Self.restHeights[index] }
        let time = date.timeIntervalSinceReferenceDate
        // Each bar wobbles at its own pace, between 55% and 100% of what the level allows.
        let wobble = 0.55 + 0.45 * (sin(time * (7 + Double(index)) + Double(index) * 1.7) * 0.5 + 0.5)
        let level = CGFloat(min(max(audioLevel, 0), 1))
        return Self.minHeight + (Self.maxHeight - Self.minHeight) * level * Self.reach[index] * wobble
    }
}
