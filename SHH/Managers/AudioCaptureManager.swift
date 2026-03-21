@preconcurrency import AVFoundation
import Combine
import Foundation

enum AudioCaptureError: Error, LocalizedError {
    case engineStartFailed(underlying: Error)
    case noInputNode
    case interrupted

    var errorDescription: String? {
        switch self {
        case .engineStartFailed(let err):
            return "Audio engine failed to start: \(err.localizedDescription)"
        case .noInputNode:
            return "No audio input device available"
        case .interrupted:
            return "Recording was interrupted"
        }
    }
}

/// Captures microphone audio at 16kHz mono Float32.
/// For recordings exceeding 5 minutes, audio is written to a temporary file
/// to limit memory usage (ADR Decision 7).
final class AudioCaptureManager {
    private let audioEngine = AVAudioEngine()
    private let targetSampleRate: Double = 16000
    private let targetChannelCount: AVAudioChannelCount = 1
    private let fiveMinuteSampleThreshold = 5 * 60 * 16000 // 4,800,000 samples

    private var audioBuffer: [Float] = []
    private var tempFileHandle: FileHandle?
    private var tempFileURL: URL?
    private var isWritingToFile = false
    private var totalSamplesWritten: Int = 0

    private(set) var isRecording = false

    /// Publishes the current audio input level (0.0–1.0) for real-time visualisation.
    let audioLevelSubject = CurrentValueSubject<Float, Never>(0.0)

    /// Called when a recording is interrupted (e.g. microphone disconnected).
    /// Delivers the samples captured up to the point of interruption.
    var onInterruption: (([Float], AudioCaptureError) -> Void)?

    private var configObserver: NSObjectProtocol?

    /// Starts capturing microphone audio.
    func startRecording() throws {
        guard !isRecording else { return }

        audioBuffer = []
        isWritingToFile = false
        totalSamplesWritten = 0
        cleanUpTempFile()

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard inputFormat.channelCount > 0 else {
            throw AudioCaptureError.noInputNode
        }

        let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: targetChannelCount,
            interleaved: false
        )!

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw AudioCaptureError.noInputNode
        }

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) {
            [weak self] buffer, _ in
            guard let self else { return }
            self.processAudioBuffer(buffer, converter: converter, targetFormat: targetFormat)
        }

        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: audioEngine,
            queue: nil
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }

        do {
            try audioEngine.start()
        } catch {
            removeConfigObserver()
            inputNode.removeTap(onBus: 0)
            throw AudioCaptureError.engineStartFailed(underlying: error)
        }

        isRecording = true
    }

    /// Stops recording and returns the captured audio samples.
    /// - Returns: Array of Float32 PCM samples at 16kHz mono.
    func stopRecording() -> [Float] {
        guard isRecording else { return [] }

        removeConfigObserver()
        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isRecording = false
        audioLevelSubject.send(0.0)

        if isWritingToFile {
            return readSamplesFromTempFile()
        } else {
            let result = audioBuffer
            audioBuffer = []
            return result
        }
    }

    // MARK: - Private

    private func processAudioBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) {
        let frameCount = AVAudioFrameCount(
            Double(buffer.frameLength) * targetSampleRate / buffer.format.sampleRate
        )
        guard frameCount > 0 else { return }

        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: targetFormat,
            frameCapacity: frameCount
        ) else { return }

        var error: NSError?
        nonisolated(unsafe) var consumed = false
        converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        guard error == nil,
              let channelData = convertedBuffer.floatChannelData,
              convertedBuffer.frameLength > 0
        else { return }

        let samples = Array(
            UnsafeBufferPointer(
                start: channelData[0],
                count: Int(convertedBuffer.frameLength)
            )
        )

        // Compute RMS audio level for real-time visualisation
        let sumOfSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        let rms = sqrt(sumOfSquares / max(Float(samples.count), 1))
        let normalised = min(rms * 4.0, 1.0) // Scale up for visual sensitivity
        audioLevelSubject.send(normalised)

        let currentTotal = isWritingToFile ? totalSamplesWritten : audioBuffer.count
        if currentTotal + samples.count > fiveMinuteSampleThreshold && !isWritingToFile {
            switchToFileStorage()
        }

        if isWritingToFile {
            writeSamplesToTempFile(samples)
        } else {
            audioBuffer.append(contentsOf: samples)
        }
    }

    private func switchToFileStorage() {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("shh_recording_\(UUID().uuidString).pcm")
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: url) else { return }

        // Write existing in-memory buffer to file
        let data = audioBuffer.withUnsafeBufferPointer { ptr in
            Data(buffer: ptr)
        }
        handle.write(data)
        totalSamplesWritten = audioBuffer.count

        audioBuffer = []
        tempFileHandle = handle
        tempFileURL = url
        isWritingToFile = true
    }

    private func writeSamplesToTempFile(_ samples: [Float]) {
        guard let handle = tempFileHandle else { return }
        let data = samples.withUnsafeBufferPointer { ptr in
            Data(buffer: ptr)
        }
        handle.write(data)
        totalSamplesWritten += samples.count
    }

    private func readSamplesFromTempFile() -> [Float] {
        tempFileHandle?.closeFile()
        tempFileHandle = nil

        guard let url = tempFileURL,
              let data = try? Data(contentsOf: url)
        else {
            cleanUpTempFile()
            return []
        }

        let count = data.count / MemoryLayout<Float>.size
        var samples = [Float](repeating: 0, count: count)
        _ = samples.withUnsafeMutableBufferPointer { ptr in
            data.copyBytes(to: ptr)
        }

        cleanUpTempFile()
        return samples
    }

    private func cleanUpTempFile() {
        tempFileHandle?.closeFile()
        tempFileHandle = nil
        if let url = tempFileURL {
            try? FileManager.default.removeItem(at: url)
            tempFileURL = nil
        }
    }

    private func handleConfigurationChange() {
        guard isRecording else { return }

        // Harvest whatever audio was captured before the interruption
        let captured = stopRecording()
        onInterruption?(captured, .interrupted)
    }

    private func removeConfigObserver() {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
            configObserver = nil
        }
    }
}
