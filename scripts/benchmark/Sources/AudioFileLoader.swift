import AVFoundation
import Foundation

/// Loads `.wav`/`.flac` (or any AVAudioFile-supported) audio and resamples it to
/// 16 kHz mono Float32 — the format `TranscriptionEngine` expects. Used only by
/// the benchmark CLI (depends on AVFoundation).
enum AudioFileLoader {
    enum LoadError: Error, CustomStringConvertible {
        case openFailed(String)
        case converterUnavailable
        case readFailed(String)

        var description: String {
            switch self {
            case let .openFailed(path): return "Failed to open audio file: \(path)"
            case .converterUnavailable: return "Could not create 16 kHz mono converter"
            case let .readFailed(message): return "Failed to read audio: \(message)"
            }
        }
    }

    static let targetSampleRate = 16_000.0

    /// Returns the decoded mono samples and the source duration in seconds.
    static func load(path: String) throws -> (samples: [Float], durationSeconds: Double) {
        let url = URL(fileURLWithPath: path)
        guard let file = try? AVAudioFile(forReading: url) else {
            throw LoadError.openFailed(path)
        }

        let sourceFormat = file.processingFormat
        let frameCount = AVAudioFrameCount(file.length)
        guard frameCount > 0 else { return ([], 0) }

        guard
            let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount)
        else {
            throw LoadError.readFailed("could not allocate source buffer")
        }
        do {
            try file.read(into: sourceBuffer)
        } catch {
            throw LoadError.readFailed(error.localizedDescription)
        }

        let durationSeconds = Double(file.length) / sourceFormat.sampleRate

        guard
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: targetSampleRate,
                channels: 1,
                interleaved: false
            ),
            let converter = AVAudioConverter(from: sourceFormat, to: targetFormat)
        else {
            throw LoadError.converterUnavailable
        }

        let ratio = targetSampleRate / sourceFormat.sampleRate
        let targetCapacity = AVAudioFrameCount(Double(frameCount) * ratio) + 1024
        guard
            let targetBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetCapacity)
        else {
            throw LoadError.readFailed("could not allocate target buffer")
        }

        var conversionError: NSError?
        let state = ConverterState(buffer: sourceBuffer)
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if state.consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            state.consumed = true
            outStatus.pointee = .haveData
            return state.buffer
        }
        let result = converter.convert(to: targetBuffer, error: &conversionError, withInputFrom: inputBlock)
        if result == .error, let conversionError {
            throw LoadError.readFailed(conversionError.localizedDescription)
        }

        let count = Int(targetBuffer.frameLength)
        guard count > 0, let channel = targetBuffer.floatChannelData?[0] else {
            return ([], durationSeconds)
        }
        let samples = Array(UnsafeBufferPointer(start: channel, count: count))
        return (samples, durationSeconds)
    }
}

/// Holds the single-shot input buffer for `AVAudioConverter`. Wrapping the
/// mutable `consumed` flag in a reference type satisfies the `@Sendable`
/// requirement on `AVAudioConverterInputBlock` under Swift 6 concurrency.
private final class ConverterState: @unchecked Sendable {
    let buffer: AVAudioPCMBuffer
    var consumed = false

    init(buffer: AVAudioPCMBuffer) {
        self.buffer = buffer
    }
}
