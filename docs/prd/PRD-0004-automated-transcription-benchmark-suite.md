---
status: Implemented
---
# PRD-0004: Automated Transcription Benchmark Suite

## 1. Problem

Every change to `WhisperTranscriber`, `AudioCaptureManager`, or the upcoming
VAD/chunker/decoder stages is currently validated by one of two methods:
the developer dictates into the app and reads the result, or a teammate
complains in chat that "it ate half my sentence." There is no objective,
repeatable measurement of transcription quality and no way to compare two
candidate configurations except by anecdote.

The whole point of PRDs 0001–0003 is to make the pipeline more accurate, and
the whole point of PRD-0005 is to stress it against adversarial datasets —
but none of those efforts mean anything without a harness that produces the
same WER and RTFx numbers on demand for any version of the code.

## 2. Problem-adjacent context

WER (Word Error Rate) is the industry-standard accuracy metric: edit
distance between the normalized reference and hypothesis transcripts,
divided by reference word count. RTFx (Real-Time Factor, inverted) is the
standard speed metric: audio seconds processed per wall-clock second. The
two together let us reason about the speed/quality trade-off when tuning
decoder parameters or considering larger Whisper models.

## 3. Objective

The system is able to take a directory of `(audio, reference)` pairs, run
SHH's real transcription pipeline (VAD → chunker → decoder → stitcher)
against every pair, compute WER and RTFx per file and in aggregate, and
emit both a human-readable report and a machine-readable JSON artefact for
diffing against previous runs.

Verifiable outcomes:

- A developer is able to run a single command and, without any manual
  setup beyond having the dataset downloaded, see a table of
  `(file, audio_seconds, transcribe_seconds, RTFx, WER)` rows and aggregate
  numbers.
- The same command on the same code and the same dataset produces
  byte-identical WER numbers across runs (determinism baked in).
- A second command compares two JSON reports and prints per-file deltas,
  flagging regressions in red.

## 4. User Flow

1. A developer runs `./scripts/benchmark-transcription.sh --dataset
   librispeech-test-clean` (or invokes the underlying Swift CLI directly).
2. The harness loads each `.wav` / `.flac` from the dataset, resamples it to
   16 kHz mono Float32 if needed, and feeds it through the same
   `TranscriptionPipeline` the app uses (VAD on, chunker on, configured
   `DecodeConfig`).
3. For each file the harness records wall-clock elapsed time, derives
   `RTFx = audio_seconds / elapsed_seconds`, normalizes both the hypothesis
   and the reference transcript with the canonical Whisper normalizer, and
   computes WER via standard Levenshtein word-edit distance.
4. After all files complete, the harness prints a table to stdout and writes
   a JSON report to `build/benchmarks/<timestamp>-<git-sha>.json` containing:
   per-file metrics, aggregate WER (micro-averaged over total reference
   words), aggregate RTFx (weighted by audio length), the active model
   identifier, the active `DecodeConfig` values, the git SHA, and the host
   machine's CPU/GPU summary.
5. The developer can then run `benchmark-transcription.sh --compare
   <old.json> <new.json>` to see per-file deltas and an aggregate verdict
   ("WER −0.7pp, RTFx +3%").
6. Alternative: the dataset directory is missing or empty. The harness
   prints a clear "dataset not found at <path>; run scripts/fetch-dataset.sh
   first" message and exits non-zero. (Dataset fetching itself is PRD-0005.)
7. Alternative: a single audio file fails to transcribe (e.g. corrupt
   header). The harness logs the failure, marks that file's WER as `null`
   in the JSON, continues with the rest of the dataset, and exits zero with
   a summary line counting failures.

## 5. Acceptance Criteria

- [ ] A new Swift executable target (or a SHHTests-adjacent CLI target) lives
  under `scripts/benchmark/` (or equivalent) and shares the production
  `TranscriptionPipeline` code path. The benchmark is forbidden from
  duplicating decode logic — it must call into the same production types.
- [ ] A canonical text normalizer (matching the Whisper English normalizer
  rules: lowercase, strip punctuation, collapse whitespace, unify
  contractions, spell out common number words) is implemented in Swift and
  unit-tested against a fixture set of input/expected pairs.
- [ ] A `WERCalculator` computes Levenshtein word-edit distance and returns
  WER as `(S + D + I) / N` per the standard formula. Unit tests cover:
  perfect match → 0.0; single substitution → `1/N`; single deletion → `1/N`;
  single insertion → `1/N`; empty hypothesis → `1.0`; empty reference →
  treated as either 0 or `nil` per a documented policy.
- [ ] An `RTFxMeasurer` wraps each transcription call with a high-resolution
  monotonic clock and exposes `RTFx = audio_seconds / elapsed_seconds`.
- [ ] The harness produces a JSON report with the schema documented in the
  PR description, including: schema version, git SHA, model name, decode
  config, host info, per-file results, aggregate WER, aggregate RTFx.
- [ ] A `--compare a.json b.json` mode prints per-file deltas and an
  aggregate verdict line. Non-zero exit code if aggregate WER regresses by
  more than a configurable threshold (default 0.5 percentage points).
- [ ] The harness runs deterministically: two consecutive runs over the same
  dataset with `temperature = 0` and the same model produce byte-identical
  per-file WER numbers. This is verified by an explicit "run-twice"
  integration test.
- [ ] Whisper context is shared across files within a single run (one model
  load, many transcriptions) to keep RTFx numbers representative of
  steady-state behaviour.
- [ ] The harness handles per-file failures without aborting the whole run:
  failures are recorded as `null` WER in the JSON and counted in the
  summary.
- [ ] Documentation under `scripts/benchmark/README.md` (or
  `docs/benchmarks.md`) explains how to run, how to compare reports, how
  to interpret numbers, and what each `DecodeConfig` knob does.
- [ ] The benchmark CLI is not invoked by `xcodebuild test` (it is too slow
  for the normal test cycle) but is wired into a separate Make target or
  script so it can be run manually and, later, by CI on demand.
