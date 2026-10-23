import Foundation

/// Counts the recordings still being transcribed (and styled), and decides which
/// ones are auto-pasted.
///
/// Recording is allowed while earlier recordings are still processing. A recording
/// started while another one is in flight is *queued*: it is transcribed and saved
/// to history like any other, but not pasted, so results don't land wherever the
/// cursor happens to be by the time they finish. Only a recording started with
/// nothing in flight is pasted.
///
/// Not thread-safe: use from the main thread only.
final class TranscriptionQueue {
    /// Recordings sent for processing that haven't finished yet.
    private(set) var pendingCount = 0

    /// Whether the recording in progress started while others were in flight.
    private var currentRecordingIsQueued = false

    /// Called whenever `pendingCount` changes.
    var onPendingCountChange: ((Int) -> Void)?

    /// Call when a recording starts.
    func recordingDidStart() {
        currentRecordingIsQueued = pendingCount > 0
    }

    /// Call when the current recording's audio is sent for processing.
    /// - Returns: whether its result should be auto-pasted.
    func enqueue() -> Bool {
        pendingCount += 1
        onPendingCountChange?(pendingCount)
        return !currentRecordingIsQueued
    }

    /// Call exactly once per `enqueue()`, when that recording has finished processing
    /// (with a transcript, no speech, or an error).
    func finish() {
        guard pendingCount > 0 else { return }
        pendingCount -= 1
        onPendingCountChange?(pendingCount)
    }
}
