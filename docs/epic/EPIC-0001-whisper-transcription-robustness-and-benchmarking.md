---
name: "EPIC-0001: Whisper Transcription Robustness and Benchmarking"
status: Implemented
---

# EPIC-0001: Whisper Transcription Robustness and Benchmarking

## 1. Goal and Vision

Eliminate the "deletion errors" and hallucinations that currently plague SHH's
push-to-talk dictation by transforming the transcription stack from a single
naïve `whisper_full` call on an unfiltered audio buffer into a deliberate,
measurable pipeline: **capture → VAD-filter → pause-aware chunk → tuned decoder
→ stitched text**.

Equally important, replace the current "ship and listen for complaints" quality
loop with a reproducible, automated benchmark that produces WER and RTFx
numbers on every change so every future tweak to the transcriber can be
defended with data instead of intuition.

The end state: SHH transcribes long, pause-heavy, noisy real-world dictation
without dropping words, and any regression in transcription quality is caught
by CI before it ships.

## 2. Scope & Boundaries

### In scope

- A Voice Activity Detection stage that runs **after** capture and **before**
  Whisper, removing silence and non-speech and exposing speech-segment
  boundaries to downstream consumers.
- A chunking strategy that splits long recordings on natural VAD-derived
  pauses rather than fixed 30-second windows, and stitches the per-chunk
  Whisper outputs back into a single transcript.
- Tuning of the Whisper decode parameters that drive robustness:
  `condition_on_previous_text` / `no_context`, temperature fallback,
  `compression_ratio_threshold`, `logprob_threshold`, and
  `no_speech_threshold`. The defaults currently hard-coded in
  `WhisperTranscriber` are replaced by a documented, benchmarked configuration.
- An automated benchmark CLI that takes a dataset of `(audio, reference)`
  pairs, runs SHH's real transcription pipeline against them, and reports
  WER and RTFx per file and aggregated.
- Integration of at least one clean dataset (LibriSpeech `test-clean`) and one
  noise-augmented condition (LibriSpeech + MUSAN or CHiME background) so the
  benchmark exercises both happy-path and adversarial conditions.

### Out of scope

- Changing the user-facing dictation UX, hotkeys, overlay widget, or style
  picker.
- Adding new languages or replacing whisper.cpp with a different engine
  (e.g. WhisperKit, faster-whisper). Those would be separate epics.
- Real-time / streaming transcription. Push-to-talk semantics (record, then
  transcribe) are preserved.
- Speaker diarization, punctuation post-processing beyond what Whisper already
  emits, or LLM-based cleanup (that lives in `TextProcessingPipeline`).
- Productionising the benchmark datasets as bundled app assets — they are
  developer-only tooling and stay outside the app bundle.

## 3. Implicit & Foundational Technical Requirements

These are prerequisites or cross-cutting concerns that any PRD in this epic
must respect.

- **VAD runtime.** Silero VAD ships as an ONNX / PyTorch model. macOS has no
  first-party ONNX runtime, so we need a decision on the inference backend
  (Core ML conversion of Silero, ONNX Runtime via SPM, or a Swift port). This
  decision is locked in PRD-0001 and consumed by all downstream PRDs.
- **Audio contract is preserved.** All stages keep operating on 16 kHz mono
  Float32 PCM (the format `AudioCaptureManager` already produces). VAD and
  chunking must not change the sample-rate contract that
  `WhisperTranscriber.transcribe` exposes.
- **Sample-accurate timing.** Chunking and stitching need sample-indexed
  segment boundaries, not seconds, to avoid off-by-one drops at chunk edges.
- **Pipeline observability.** `PipelineEventLog` is the existing channel for
  diagnostic events; every new stage (VAD, chunker, decoder fallback) must
  emit structured events through it so the benchmark and the in-app debug
  overlay both see the same story.
- **Deterministic benchmarks.** Whisper with `temperature=0` and a fixed
  beam size must produce byte-identical text on repeat runs of the same
  audio. The benchmark harness asserts this so flaky CI runs are caught.
- **Text normalization for WER.** WER must be computed against a canonical
  Whisper-style normalizer (lowercase, punctuation stripped, number-words
  unified) so SHH's numbers are comparable to published Whisper baselines.
- **Dataset hygiene.** Dataset files (LibriSpeech, MUSAN/CHiME) are gitignored
  and fetched on demand by a script. They never enter the app bundle and never
  enter the repo.
- **No regressions in the existing push-to-talk path.** Short utterances
  (< 5 s, single chunk) must remain at least as fast and at least as accurate
  as today's pipeline once the new stages land. The benchmark suite owns the
  proof.

## 4. PRD Roadmap

- [x] PRD-0001: VAD Pre-processing Pipeline (Silero VAD integration)
- [x] PRD-0002: VAD-Driven Intelligent Chunking and Stitching
- [x] PRD-0003: Whisper Decoder Parameter Tuning and Confidence Fallback
- [x] PRD-0004: Automated Transcription Benchmark Suite (WER and RTFx)
- [x] PRD-0005: Dataset Stress Testing Harness (LibriSpeech, MUSAN, CHiME)
