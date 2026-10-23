import Foundation

/// A speech-bearing slice of audio sized to fit comfortably inside Whisper's
/// 30 s processing window. A chunk's samples are the concatenation of the VAD
/// speech segments assigned to it (inter-segment silence is dropped), so every
/// chunk boundary falls inside a pause and never inside a word.
struct AudioChunk: Equatable {
    /// The chunk's audio: concatenated samples of its constituent segments.
    let samples: [Float]
    /// Inclusive start sample index of the first segment in the original buffer.
    let startSample: Int
    /// Exclusive end sample index of the last segment in the original buffer.
    let endSample: Int

    var sampleCount: Int { samples.count }
}

/// Tunable parameters for grouping VAD segments into Whisper-sized chunks.
struct ChunkConfig: Equatable {
    /// Audio sample rate the buffers are expressed at (16 kHz for Whisper).
    var sampleRate: Int

    /// Maximum audio samples per chunk. 28 s at 16 kHz leaves a 2 s safety
    /// margin below Whisper's 30 s internal window.
    var maxChunkSamples: Int

    /// Window (in samples) searched backward from the max-chunk boundary when a
    /// single segment is too long to fit and must be force-split. The lowest
    /// energy frame in this window becomes the cut point. 2 s at 16 kHz.
    var forcedSplitWindowSamples: Int

    /// Frame size (in samples) used when scanning for the lowest-energy cut
    /// point during a forced split. 1600 == 100 ms at 16 kHz.
    var forcedSplitFrameSamples: Int

    static let `default` = ChunkConfig(
        sampleRate: 16_000,
        maxChunkSamples: 28 * 16_000,
        forcedSplitWindowSamples: 2 * 16_000,
        forcedSplitFrameSamples: 1600
    )

    init(sampleRate: Int, maxChunkSamples: Int, forcedSplitWindowSamples: Int, forcedSplitFrameSamples: Int) {
        self.sampleRate = max(1, sampleRate)
        self.maxChunkSamples = max(1, maxChunkSamples)
        self.forcedSplitWindowSamples = max(1, forcedSplitWindowSamples)
        self.forcedSplitFrameSamples = max(1, forcedSplitFrameSamples)
    }
}

/// The result of planning: the ordered chunks plus the sample indices at which
/// forced splits had to be introduced (for diagnostic logging).
struct ChunkPlan: Equatable {
    let chunks: [AudioChunk]
    /// Sample indices where an over-long segment was force-split. Empty when no
    /// segment exceeded the max chunk duration.
    let forcedSplitIndices: [Int]
}

/// Pure, deterministic grouping of VAD speech segments into Whisper-sized
/// chunks. Free of any whisper.cpp dependency so it can be exhaustively unit
/// tested without linking the native runtime.
enum TranscriptionChunker {
    /// Groups speech segments into ordered chunks, each no longer than the
    /// configured max duration, with boundaries only inside pauses (or, for an
    /// over-long single segment, at its lowest-energy frame).
    ///
    /// - Parameters:
    ///   - buffer: The full source buffer the segments index into.
    ///   - segments: Ascending, non-overlapping VAD speech segments.
    ///   - config: Chunking parameters.
    /// - Returns: An ordered `ChunkPlan`. Empty when there are no segments.
    static func chunk(
        buffer: [Float],
        segments: [SpeechSegment],
        config: ChunkConfig = .default
    ) -> ChunkPlan {
        guard !segments.isEmpty, !buffer.isEmpty else {
            return ChunkPlan(chunks: [], forcedSplitIndices: [])
        }

        // 1. Split any segment longer than the max chunk into bounded pieces.
        var workSegments: [SpeechSegment] = []
        var forcedSplitIndices: [Int] = []
        for segment in segments {
            let start = max(0, segment.start)
            let end = min(buffer.count, segment.end)
            guard end > start else { continue }

            if end - start <= config.maxChunkSamples {
                workSegments.append(SpeechSegment(start: start, end: end))
                continue
            }

            var pieceStart = start
            while end - pieceStart > config.maxChunkSamples {
                let splitIndex = lowestEnergySplit(
                    buffer: buffer,
                    rangeStart: pieceStart,
                    rangeEnd: end,
                    config: config
                )
                workSegments.append(SpeechSegment(start: pieceStart, end: splitIndex))
                forcedSplitIndices.append(splitIndex)
                pieceStart = splitIndex
            }
            workSegments.append(SpeechSegment(start: pieceStart, end: end))
        }

        // 2. Greedily pack segments into chunks up to the max duration.
        var chunks: [AudioChunk] = []
        var current: [SpeechSegment] = []
        var currentCount = 0
        for segment in workSegments {
            if !current.isEmpty, currentCount + segment.sampleCount > config.maxChunkSamples {
                chunks.append(makeChunk(buffer: buffer, segments: current))
                current = []
                currentCount = 0
            }
            current.append(segment)
            currentCount += segment.sampleCount
        }
        if !current.isEmpty {
            chunks.append(makeChunk(buffer: buffer, segments: current))
        }

        return ChunkPlan(chunks: chunks, forcedSplitIndices: forcedSplitIndices)
    }

    // MARK: - Private

    /// Concatenates the samples of the given segments into a single chunk.
    private static func makeChunk(buffer: [Float], segments: [SpeechSegment]) -> AudioChunk {
        var samples: [Float] = []
        samples.reserveCapacity(segments.reduce(0) { $0 + $1.sampleCount })
        for segment in segments {
            let start = max(0, segment.start)
            let end = min(buffer.count, segment.end)
            if end > start {
                samples.append(contentsOf: buffer[start..<end])
            }
        }
        return AudioChunk(
            samples: samples,
            startSample: segments.first?.start ?? 0,
            endSample: segments.last?.end ?? 0
        )
    }

    /// Finds the start index of the lowest-energy frame within the acceptable
    /// cut window `[rangeStart + max - window, rangeStart + max]`, clamped to
    /// `rangeEnd`. Guarantees a result strictly greater than `rangeStart`.
    private static func lowestEnergySplit(
        buffer: [Float],
        rangeStart: Int,
        rangeEnd: Int,
        config: ChunkConfig
    ) -> Int {
        let hardLimit = min(rangeEnd, rangeStart + config.maxChunkSamples)
        let windowStart = max(rangeStart + 1, hardLimit - config.forcedSplitWindowSamples)
        let frame = config.forcedSplitFrameSamples

        var bestIndex = hardLimit
        var bestEnergy = Float.greatestFiniteMagnitude
        var frameStart = windowStart
        while frameStart < hardLimit {
            let frameEnd = min(frameStart + frame, hardLimit)
            var energy: Float = 0
            for sample in buffer[frameStart..<frameEnd] {
                energy += sample * sample
            }
            // Compare mean energy so unequal final-frame widths are fair.
            let meanEnergy = energy / Float(max(1, frameEnd - frameStart))
            if meanEnergy < bestEnergy {
                bestEnergy = meanEnergy
                bestIndex = frameStart
            }
            frameStart += frame
        }

        // Never return a degenerate split that fails to make progress.
        return min(max(bestIndex, rangeStart + 1), hardLimit)
    }
}
