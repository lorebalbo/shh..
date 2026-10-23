# 1. Transcription Benchmarking

This document describes the automated benchmark harness for the SHH Whisper
transcription pipeline. The benchmark measures transcription accuracy (Word
Error Rate, WER) and speed (Real-Time Factor, RTFx) over a labelled dataset,
producing a machine-readable JSON report that can be diffed across commits to
catch regressions.

## 2. Architecture

The benchmark is a standalone command-line tool (`shh-benchmark`) that shares
the exact production transcription code path. It does not duplicate any decode
logic.

The shared orchestration lives in `TranscriptionEngine`, which both the app's
`TranscriptionPipeline` and the benchmark CLI call:
- VAD segmentation (`VADProcessor` / `VADSegmentBuilder`)
- Intelligent chunking (`TranscriptionChunker`)
- Temperature-fallback decoding (`WhisperTranscriber` / `DecodeConfig`)
- Transcript stitching (`TranscriptStitcher`)

The benchmark adds only measurement concerns on top:
- `WhisperTextNormalizer` — canonicalizes text before scoring (casing,
  punctuation, contractions, number words).
- `WERCalculator` — Levenshtein word-edit distance, `WER = (S + D + I) / N`.
- `RTFxMeasurer` — monotonic-clock timing, `RTFx = audio_seconds / elapsed`.
- `BenchmarkReport` — Codable JSON schema plus aggregation and comparison.

## 3. Running a Benchmark

Use the wrapper script. It regenerates the project, builds the CLI, and runs it:
```bash
./scripts/benchmark-transcription.sh \
    --model     /path/to/ggml-model.bin \
    --vad-model /path/to/ggml-silero-v5.1.2.bin \
    --manifest  /path/to/manifest.json \
    [--language auto] \
    [--output   report.json]
```

When `--output` is omitted, the report is written to
`build/benchmarks/<timestamp>-<git-sha>.json`.

### 3.1. Manifest Format

The manifest is a JSON array of audio files paired with their ground-truth
transcripts. Relative `audio` paths are resolved against the manifest's own
directory:
```json
[
  { "audio": "a.wav", "reference": "The quick brown fox jumps over the lazy dog" },
  { "audio": "b.flac", "reference": "She sells sea shells by the sea shore" }
]
```

Audio may be `.wav`, `.flac`, or any format AVFoundation can read. Files are
resampled to 16 kHz mono Float32 before transcription.

### 3.2. Report Schema

Each report records the schema version, git SHA, model name, the active decode
configuration, host info, per-file results (audio duration, transcribe time,
RTFx, WER and the S/D/I edit breakdown), and an aggregate block. Aggregate WER
is micro-averaged (total edits over total reference words); aggregate RTFx is
audio-length-weighted.

A per-file transcription failure records a `null` WER row with `failed: true`,
does not abort the run, and does not change the process exit code.

## 4. Comparing Reports

To compare a candidate report against a baseline:
```bash
./scripts/benchmark-transcription.sh --compare baseline.json candidate.json
```

The comparison prints per-file WER deltas and an aggregate verdict. It exits
non-zero when aggregate WER regresses by more than 0.5 percentage points, so it
can gate CI.

## 5. Determinism

With a fixed model, decode configuration and input, the benchmark is
deterministic: repeated runs produce identical transcripts, identical per-file
WER, and an identical aggregate WER. Only RTFx varies between runs (it depends
on wall-clock timing), which is expected and is not used for regression gating.

## 6. Datasets and Stress Testing

Standard public datasets exercise the pipeline far beyond a few desk
recordings. They are fetched into a gitignored cache (default
`~/.cache/shh-benchmarks`, override with `SHH_BENCHMARK_CACHE`) and never enter
the repo or the app bundle.

### 6.1. Fetching a Dataset

Each registered dataset is prepared with one command; re-runs are idempotent:
```bash
./scripts/fetch-dataset.sh librispeech-test-clean
./scripts/fetch-dataset.sh librispeech-test-clean --dry-run   # print size only
```

Registered datasets and approximate disk usage:
- `librispeech-test-clean` — read English speech, clean (~346 MB)
- `librispeech-test-other` — read English speech, harder (~328 MB)
- `musan` — music/speech/noise corpus for augmentation (~11 GB)
- `chime6` — real-world noisy speech, licence-restricted (~165 GB, manual)

Licence-restricted datasets such as CHiME are never auto-downloaded: the fetch
script prints the required download URL and target path, then exits non-zero.

After a fetch, the dataset has a `manifest.json` at
`<cache>/datasets/<name>/manifest.json` listing `{audio, reference,
duration_seconds}` entries, which the benchmark consumes directly:
```bash
./scripts/benchmark-transcription.sh \
    --model SHH/Resources/ggml-base.bin \
    --vad-model SHH/Resources/ggml-silero-v5.1.2.bin \
    --dataset librispeech-test-clean
```

### 6.2. Noise Augmentation

To stress the pipeline with background noise, fetch a noise corpus once, then
mix it into a clean dataset at a chosen signal-to-noise ratio. The clean
reference transcript is preserved, so WER is measured against ground truth:
```bash
./scripts/fetch-dataset.sh musan
./scripts/augment-dataset.sh \
    --source librispeech-test-clean \
    --noise  musan \
    --snr    10 \
    --output librispeech-clean-musan-10db \
    --seed   42
```

`--snr` accepts a list (e.g. `0,10,20`) to emit one dataset per level. `--seed`
makes the random noise selection reproducible: the same seed yields byte-identical
mixed audio.

### 6.3. Full Workflow

The complete stress-test loop, fetching clean speech, benchmarking it, adding
noise, and comparing:
```bash
# 1. Clean baseline.
./scripts/fetch-dataset.sh librispeech-test-clean
./scripts/benchmark-transcription.sh --model M --vad-model V \
    --dataset librispeech-test-clean --output clean.json

# 2. Add noise and benchmark the noisy variant.
./scripts/fetch-dataset.sh musan
./scripts/augment-dataset.sh --source librispeech-test-clean --noise musan \
    --snr 10 --output librispeech-clean-musan-10db
./scripts/benchmark-transcription.sh --model M --vad-model V \
    --dataset librispeech-clean-musan-10db --output noisy.json

# 3. Compare (non-zero exit if WER regresses beyond threshold).
./scripts/benchmark-transcription.sh --compare clean.json noisy.json
```
