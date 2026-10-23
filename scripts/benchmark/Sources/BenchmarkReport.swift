import Foundation

/// Machine-readable benchmark report schema. Codable so a run can be persisted
/// to `build/benchmarks/<timestamp>-<git-sha>.json` and diffed against a prior
/// run. Pure data — no whisper.cpp dependency — so the schema and the compare
/// logic are unit tested directly.
struct BenchmarkReport: Codable, Equatable {
    /// Bumped whenever the schema changes in a backward-incompatible way.
    static let schemaVersion = 1

    var schemaVersion: Int = BenchmarkReport.schemaVersion
    var gitSHA: String
    var modelName: String
    var decodeConfig: DecodeConfigSnapshot
    var host: HostInfo
    var files: [FileResult]
    var aggregate: Aggregate

    /// A flattened, JSON-friendly copy of the active `DecodeConfig`.
    struct DecodeConfigSnapshot: Codable, Equatable {
        var temperatures: [Float]
        var compressionRatioThreshold: Float
        var logprobThreshold: Float
        var noSpeechThreshold: Float
        var conditionOnPreviousText: Bool
        var beamSize: Int
    }

    struct HostInfo: Codable, Equatable {
        var osVersion: String
        var cpuCores: Int
        var physicalMemoryBytes: UInt64
    }

    struct FileResult: Codable, Equatable {
        var file: String
        var audioSeconds: Double
        var transcribeSeconds: Double
        var rtfx: Double?
        /// `null` when the file failed to transcribe.
        var wer: Double?
        var referenceWords: Int
        var substitutions: Int
        var deletions: Int
        var insertions: Int
        var failed: Bool
    }

    struct Aggregate: Codable, Equatable {
        /// Micro-averaged WER over total reference words across all files.
        var wer: Double?
        /// Audio-length-weighted RTFx across all files.
        var rtfx: Double?
        var totalFiles: Int
        var failedFiles: Int
        var totalAudioSeconds: Double
        var totalTranscribeSeconds: Double
    }
}

/// Builds the aggregate block from per-file results using micro-averaging for
/// WER (total edits / total reference words) and audio-weighted RTFx.
enum BenchmarkAggregator {
    static func aggregate(_ files: [BenchmarkReport.FileResult]) -> BenchmarkReport.Aggregate {
        var totalEdits = 0
        var totalRefWords = 0
        var totalAudio = 0.0
        var totalTranscribe = 0.0
        var failed = 0

        for file in files {
            if file.failed { failed += 1; continue }
            totalEdits += file.substitutions + file.deletions + file.insertions
            totalRefWords += file.referenceWords
            totalAudio += file.audioSeconds
            totalTranscribe += file.transcribeSeconds
        }

        let wer: Double? = totalRefWords > 0 ? Double(totalEdits) / Double(totalRefWords) : nil
        let rtfx: Double? = totalTranscribe > 0 ? totalAudio / totalTranscribe : nil

        return BenchmarkReport.Aggregate(
            wer: wer,
            rtfx: rtfx,
            totalFiles: files.count,
            failedFiles: failed,
            totalAudioSeconds: totalAudio,
            totalTranscribeSeconds: totalTranscribe
        )
    }
}

/// Compares two reports and produces per-file deltas plus an aggregate verdict.
enum BenchmarkComparison {
    struct FileDelta: Equatable {
        let file: String
        let werBefore: Double?
        let werAfter: Double?
        let rtfxBefore: Double?
        let rtfxAfter: Double?

        /// Positive = WER got worse (more errors).
        var werDelta: Double? {
            guard let before = werBefore, let after = werAfter else { return nil }
            return after - before
        }
    }

    struct Verdict: Equatable {
        let aggregateWERBefore: Double?
        let aggregateWERAfter: Double?
        let aggregateRTFxBefore: Double?
        let aggregateRTFxAfter: Double?
        let fileDeltas: [FileDelta]
        /// True when aggregate WER regressed by more than the threshold.
        let regressed: Bool

        /// Aggregate WER change in percentage points (after − before).
        var werDeltaPP: Double? {
            guard let before = aggregateWERBefore, let after = aggregateWERAfter else { return nil }
            return (after - before) * 100
        }
    }

    /// Compares `before` and `after`, flagging a regression when aggregate WER
    /// rises by more than `thresholdPP` percentage points (default 0.5).
    static func compare(
        before: BenchmarkReport,
        after: BenchmarkReport,
        thresholdPP: Double = 0.5
    ) -> Verdict {
        let beforeByFile = Dictionary(uniqueKeysWithValues: before.files.map { ($0.file, $0) })
        var deltas: [FileDelta] = []
        for afterFile in after.files {
            let beforeFile = beforeByFile[afterFile.file]
            deltas.append(
                FileDelta(
                    file: afterFile.file,
                    werBefore: beforeFile?.wer,
                    werAfter: afterFile.wer,
                    rtfxBefore: beforeFile?.rtfx,
                    rtfxAfter: afterFile.rtfx
                )
            )
        }

        var regressed = false
        if let wBefore = before.aggregate.wer, let wAfter = after.aggregate.wer {
            regressed = (wAfter - wBefore) * 100 > thresholdPP
        }

        return Verdict(
            aggregateWERBefore: before.aggregate.wer,
            aggregateWERAfter: after.aggregate.wer,
            aggregateRTFxBefore: before.aggregate.rtfx,
            aggregateRTFxAfter: after.aggregate.rtfx,
            fileDeltas: deltas,
            regressed: regressed
        )
    }
}
