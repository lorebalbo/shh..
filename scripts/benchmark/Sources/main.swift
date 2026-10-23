import Foundation

// MARK: - Argument parsing

struct Arguments {
    var model: String?
    var vadModel: String?
    var manifest: String?
    var dataset: String?
    var output: String?
    var language = "auto"
    var compare: (before: String, after: String)?

    static func parse(_ argv: [String]) -> Arguments {
        var args = Arguments()
        var index = 0
        while index < argv.count {
            let arg = argv[index]
            func next() -> String? {
                index += 1
                return index < argv.count ? argv[index] : nil
            }
            switch arg {
            case "--model": args.model = next()
            case "--vad-model": args.vadModel = next()
            case "--manifest": args.manifest = next()
            case "--dataset": args.dataset = next()
            case "--output": args.output = next()
            case "--language": args.language = next() ?? "auto"
            case "--compare":
                let before = next()
                let after = next()
                if let before, let after { args.compare = (before, after) }
            default: break
            }
            index += 1
        }
        return args
    }
}

/// Resolves a registered dataset name to its prepared `manifest.json` path under
/// the benchmark cache root (`$SHH_BENCHMARK_CACHE` or `~/.cache/shh-benchmarks`).
func resolveDatasetManifest(_ name: String) -> String {
    let env = ProcessInfo.processInfo.environment
    let root = env["SHH_BENCHMARK_CACHE"]
        ?? (env["HOME"].map { "\($0)/.cache/shh-benchmarks" } ?? ".cache/shh-benchmarks")
    return "\(root)/datasets/\(name)/manifest.json"
}

/// One audio file plus its ground-truth transcript. `durationSeconds` is an
/// optional hint produced by the dataset preparation scripts; it is not used
/// for scoring (the true duration is read from the decoded audio).
struct ManifestEntry: Codable {
    let audio: String
    let reference: String
    let durationSeconds: Double?

    enum CodingKeys: String, CodingKey {
        case audio
        case reference
        case durationSeconds = "duration_seconds"
    }
}

// MARK: - Helpers

func gitSHA() -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["git", "rev-parse", "--short", "HEAD"]
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = Pipe()
    do {
        try process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let sha = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (sha?.isEmpty == false ? sha : "unknown") ?? "unknown"
    } catch {
        return "unknown"
    }
}

func hostInfo() -> BenchmarkReport.HostInfo {
    let info = ProcessInfo.processInfo
    return BenchmarkReport.HostInfo(
        osVersion: info.operatingSystemVersionString,
        cpuCores: info.processorCount,
        physicalMemoryBytes: info.physicalMemory
    )
}

func snapshot(_ config: DecodeConfig) -> BenchmarkReport.DecodeConfigSnapshot {
    BenchmarkReport.DecodeConfigSnapshot(
        temperatures: config.temperatures,
        compressionRatioThreshold: config.compressionRatioThreshold,
        logprobThreshold: config.logprobThreshold,
        noSpeechThreshold: config.noSpeechThreshold,
        conditionOnPreviousText: config.conditionOnPreviousText,
        beamSize: config.beamSize
    )
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    cleanExit(2)
}

/// Terminates the process via `_exit` after flushing stdio. This deliberately
/// skips C++ static destructors: whisper.cpp's Metal backend asserts during
/// `__cxa_finalize` teardown (residency sets not yet released) on pre-M5 GPUs,
/// which would otherwise turn a successful run into a non-zero abort. All work
/// and output are already complete by the time this is called.
func cleanExit(_ code: Int32) -> Never {
    fflush(stdout)
    fflush(stderr)
    _exit(code)
}

// MARK: - Compare mode

func runCompare(before beforePath: String, after afterPath: String) -> Never {
    let decoder = JSONDecoder()
    guard
        let beforeData = try? Data(contentsOf: URL(fileURLWithPath: beforePath)),
        let before = try? decoder.decode(BenchmarkReport.self, from: beforeData)
    else { fail("could not read baseline report at \(beforePath)") }
    guard
        let afterData = try? Data(contentsOf: URL(fileURLWithPath: afterPath)),
        let after = try? decoder.decode(BenchmarkReport.self, from: afterData)
    else { fail("could not read candidate report at \(afterPath)") }

    let verdict = BenchmarkComparison.compare(before: before, after: after)

    print("Benchmark comparison")
    print("  baseline:  \(beforePath)")
    print("  candidate: \(afterPath)")
    print("")
    func fmtWER(_ value: Double?) -> String {
        value.map { String(format: "%.2f%%", $0 * 100) } ?? "n/a"
    }
    func fmtRTFx(_ value: Double?) -> String {
        value.map { String(format: "%.2fx", $0) } ?? "n/a"
    }
    for delta in verdict.fileDeltas {
        let arrow = (delta.werDelta ?? 0) > 0 ? "▲" : (delta.werDelta ?? 0) < 0 ? "▼" : "="
        print("  \(arrow) \(delta.file): WER \(fmtWER(delta.werBefore)) -> \(fmtWER(delta.werAfter))")
    }
    print("")
    print("  aggregate WER:  \(fmtWER(verdict.aggregateWERBefore)) -> \(fmtWER(verdict.aggregateWERAfter))")
    print("  aggregate RTFx: \(fmtRTFx(verdict.aggregateRTFxBefore)) -> \(fmtRTFx(verdict.aggregateRTFxAfter))")
    if let deltaPP = verdict.werDeltaPP {
        print(String(format: "  WER delta:      %+.2f pp", deltaPP))
    }
    if verdict.regressed {
        print("  verdict: REGRESSION (WER increased beyond threshold)")
        exit(1)
    }
    print("  verdict: OK")
    exit(0)
}

// MARK: - Run mode

func runBenchmark(_ args: Arguments) -> Never {
    guard let modelPath = args.model else { fail("--model is required") }
    let manifestPath: String
    if let explicit = args.manifest {
        manifestPath = explicit
    } else if let dataset = args.dataset {
        manifestPath = resolveDatasetManifest(dataset)
    } else {
        fail("one of --manifest or --dataset is required")
    }

    guard
        let manifestData = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
        let entries = try? JSONDecoder().decode([ManifestEntry].self, from: manifestData)
    else { fail("could not read manifest at \(manifestPath)") }

    let manifestDir = URL(fileURLWithPath: manifestPath).deletingLastPathComponent()

    let transcriber: WhisperTranscriber
    do {
        transcriber = try WhisperTranscriber(modelPath: modelPath)
    } catch {
        fail("could not load whisper model: \(error)")
    }

    let vad: VADProcessor?
    if let vadModelPath = args.vadModel {
        // VAD runs on CPU here: the tiny Silero model trips a Metal backend
        // assertion in this CLI context, and CPU inference of an ~0.9 MB model
        // is negligible. Whisper decode still uses the GPU.
        vad = VADProcessor(modelPath: vadModelPath, useGPU: false)
    } else {
        vad = nil
    }

    let decodeConfig = DecodeConfig.default
    var fileResults: [BenchmarkReport.FileResult] = []
    let totalFiles = entries.count

    for (index, entry) in entries.enumerated() {
        let audioPath = entry.audio.hasPrefix("/")
            ? entry.audio
            : manifestDir.appendingPathComponent(entry.audio).path
        let name = URL(fileURLWithPath: audioPath).lastPathComponent

        do {
            let (samples, durationSeconds) = try AudioFileLoader.load(path: audioPath)
            let normalized = TranscriptionEngine.normalize(samples)
            let measurement = try RTFxMeasurer.measure(audioSeconds: durationSeconds) {
                try TranscriptionEngine.run(
                    normalizedBuffer: normalized,
                    transcriber: transcriber,
                    vad: vad,
                    language: args.language,
                    decodeConfig: decodeConfig
                )
            }
            let wer = WERCalculator.compute(
                referenceText: entry.reference,
                hypothesisText: measurement.value
            )
            let result = BenchmarkReport.FileResult(
                    file: name,
                    audioSeconds: durationSeconds,
                    transcribeSeconds: measurement.elapsedSeconds,
                    rtfx: measurement.rtfx,
                    wer: wer.wer,
                    referenceWords: wer.referenceWords,
                    substitutions: wer.substitutions,
                    deletions: wer.deletions,
                    insertions: wer.insertions,
                    failed: false
                )
            fileResults.append(result)
            let werText = wer.wer.map { String(format: "%.2f%%", $0 * 100) } ?? "n/a"
            let rtfxText = measurement.rtfx.map { String(format: "%.2fx", $0) } ?? "n/a"

            // Running aggregate
            let running = BenchmarkAggregator.aggregate(fileResults)
            let runningWER = running.wer.map { String(format: "%.2f%%", $0 * 100) } ?? "n/a"

            print("  ✅ [\(index + 1)/\(totalFiles)] \(name): WER \(werText), RTFx \(rtfxText) — running WER \(runningWER)")
            print("     hyp: \(measurement.value)")
        } catch {
            // Per-file failure: record a null-WER row and keep going.
            fileResults.append(
                BenchmarkReport.FileResult(
                    file: name,
                    audioSeconds: 0,
                    transcribeSeconds: 0,
                    rtfx: nil,
                    wer: nil,
                    referenceWords: 0,
                    substitutions: 0,
                    deletions: 0,
                    insertions: 0,
                    failed: true
                )
            )
            let running = BenchmarkAggregator.aggregate(fileResults)
            let runningWER = running.wer.map { String(format: "%.2f%%", $0 * 100) } ?? "n/a"
            FileHandle.standardError.write(Data("  ❌ [\(index + 1)/\(totalFiles)] \(name): \(error) — running WER \(runningWER)\n".utf8))
        }
    }

    let aggregate = BenchmarkAggregator.aggregate(fileResults)
    let report = BenchmarkReport(
        gitSHA: gitSHA(),
        modelName: URL(fileURLWithPath: modelPath).lastPathComponent,
        decodeConfig: snapshot(decodeConfig),
        host: hostInfo(),
        files: fileResults,
        aggregate: aggregate
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let json = try? encoder.encode(report) else { fail("could not encode report") }

    let outputPath: String
    if let provided = args.output {
        outputPath = provided
    } else {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stamp = formatter.string(from: Date())
        let dir = "build/benchmarks"
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        outputPath = "\(dir)/\(stamp)-\(report.gitSHA).json"
    }

    do {
        let url = URL(fileURLWithPath: outputPath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try json.write(to: url)
    } catch {
        fail("could not write report to \(outputPath): \(error)")
    }

    let aggWER = aggregate.wer.map { String(format: "%.2f%%", $0 * 100) } ?? "n/a"
    let aggRTFx = aggregate.rtfx.map { String(format: "%.2fx", $0) } ?? "n/a"
    print("")
    print("Aggregate WER:  \(aggWER)")
    print("Aggregate RTFx: \(aggRTFx)")
    print("Report written: \(outputPath)")
    cleanExit(0)
}

// MARK: - Entry point

let arguments = Arguments.parse(Array(CommandLine.arguments.dropFirst()))
if let compare = arguments.compare {
    runCompare(before: compare.before, after: compare.after)
}
runBenchmark(arguments)
