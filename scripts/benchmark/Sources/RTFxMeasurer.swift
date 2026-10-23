import Foundation

/// Wraps a unit of work with a high-resolution monotonic clock and reports the
/// Real-Time Factor (inverted): audio seconds processed per wall-clock second.
/// Higher is faster; RTFx > 1 means faster-than-real-time.
///
/// Pure and deterministic in its arithmetic — no whisper.cpp dependency — so the
/// RTFx computation is unit tested directly.
enum RTFxMeasurer {
    /// The outcome of a timed transcription.
    struct Measurement<T>: Equatable where T: Equatable {
        let value: T
        let audioSeconds: Double
        let elapsedSeconds: Double

        /// audio_seconds / elapsed_seconds. `nil` when no wall-clock time
        /// elapsed (degenerate; avoids divide-by-zero).
        var rtfx: Double? {
            guard elapsedSeconds > 0 else { return nil }
            return audioSeconds / elapsedSeconds
        }
    }

    /// Runs `work`, timing it with a monotonic clock, and returns the produced
    /// value alongside the audio/elapsed durations.
    static func measure<T>(
        audioSeconds: Double,
        _ work: () throws -> T
    ) rethrows -> Measurement<T> where T: Equatable {
        let start = DispatchTime.now().uptimeNanoseconds
        let value = try work()
        let end = DispatchTime.now().uptimeNanoseconds
        let elapsed = Double(end - start) / 1_000_000_000
        return Measurement(value: value, audioSeconds: audioSeconds, elapsedSeconds: elapsed)
    }

    /// Computes RTFx directly from two durations.
    static func rtfx(audioSeconds: Double, elapsedSeconds: Double) -> Double? {
        guard elapsedSeconds > 0 else { return nil }
        return audioSeconds / elapsedSeconds
    }
}
