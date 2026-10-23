---
status: Implemented
---
# PRD-0003: Whisper Decoder Parameter Tuning and Confidence Fallback

## 1. Problem

`WhisperTranscriber` currently hard-codes a single decode configuration:
beam search with `beam_size = 5`, `no_speech_thold = 0.9`, `no_context = true`,
`suppress_blank = false`, and no temperature fallback. Each of those values
was set in isolation as a reaction to a specific bug (long pauses deleting
text, blanks suppressing post-pause speech, etc.). The combination has never
been measured against a labelled dataset, and several of the OpenAI
upstream defaults that exist *specifically* to combat hallucinations are
silently bypassed:

- `temperature_increment_on_fallback` / `temperatures = [0.0, 0.2, 0.4, 0.6,
  0.8, 1.0]` — the standard "if the greedy/beam decode is low-confidence,
  retry with more entropy" loop. Without it, whisper.cpp commits to a
  hallucinated repetition on its first try and never reconsiders.
- `compression_ratio_threshold = 2.4` — detects the classic "loop"
  hallucination ("thank you. thank you. thank you. ...") and triggers the
  fallback. Disabled by default in whisper.cpp's API; SHH never enables it.
- `logprob_threshold = -1.0` — detects low-likelihood segments and triggers
  the fallback. Same situation.
- `condition_on_previous_text` — currently forced *off* via
  `no_context = true` because of the deletion bug in PRD-0001's scope. Once
  VAD + chunking land, that mitigation is no longer the right default; we
  want to feed previous-chunk tokens as a prompt for continuity, with a
  guard against repetition loops.

The user sees this as occasional "thank you thank you thank you" runs at the
end of recordings, words from one chunk bleeding into the next, and silent
deletions in noisy conditions.

## 2. Objective

The system is able to transcribe each chunk with a confidence-aware decoder
that retries with increasing temperature when the result fails compression
or log-probability checks, and that conditions on the previous chunk's
tokens when (and only when) the previous chunk's decode was confident. The
final parameter set is documented in code and benchmarked in PRD-0004 against
a labelled dataset, replacing today's intuition-driven defaults.

Verifiable outcomes:

- Looping hallucinations ("thank you. thank you. ...") are caught by the
  compression-ratio check and resolved by the fallback ladder in ≥ 95% of
  cases on the benchmark dataset.
- Cross-chunk continuity (e.g. a name spelled out in chunk 1 is spelled
  correctly in chunk 2) is preserved when the prompt-passing path is active.
- WER on LibriSpeech `test-clean` (PRD-0005) improves vs. the
  pre-PRD-0003 baseline, and WER on the noise-augmented condition improves
  by a documented target margin.

## 3. User Flow

1. The user finishes dictating; chunks reach `WhisperTranscriber` (PRD-0002).
2. For each chunk, `WhisperTranscriber.transcribe` runs the decoder with the
   primary configuration (`temperature = 0.0`, beam search).
3. After each chunk, the transcriber computes two confidence signals from
   the segment-level outputs whisper.cpp exposes: the compression ratio of
   the chunk's text vs. its byte length, and the average per-token log
   probability.
4. If either signal is outside the configured threshold, the transcriber
   retries the same chunk with the next temperature on the ladder
   (`0.2 → 0.4 → 0.6 → 0.8 → 1.0`). The first attempt that passes both
   thresholds wins; if none pass, the highest-temperature attempt is kept
   and a `decoder.fallback_exhausted` event is logged.
5. Between chunks, the transcriber passes the last confident chunk's last
   N tokens as the `initial_prompt` for the next chunk. If the previous
   chunk required a high-temperature fallback, the prompt is suppressed for
   the next chunk to prevent error propagation.
6. The user sees the final stitched transcript exactly as today; the
   fallback behaviour is invisible in the overlay but visible in the
   debug log.
7. Alternative: a single chunk fails every fallback step. The transcriber
   keeps the best-of-N output, logs the failure, and lets the stitcher
   include it. The recording is never wholly discarded because one chunk
   was noisy.

## 4. Acceptance Criteria

- [ ] `WhisperTranscriber.transcribe` accepts an explicit `DecodeConfig`
  parameter (struct with: `temperatures`, `compressionRatioThreshold`,
  `logprobThreshold`, `noSpeechThreshold`, `conditionOnPreviousText`,
  `beamSize`, `initialPrompt`). The current hard-coded values become the
  defaults of `DecodeConfig`.
- [ ] The transcriber implements the temperature fallback ladder. After each
  attempt it reads per-segment `avg_logprob` and computes compression ratio
  on the concatenated text; if either fails, it retries with the next
  temperature.
- [ ] When the temperature is 0, beam search with the configured
  `beamSize` is used. For non-zero temperatures, sampling is used (matching
  upstream Whisper behaviour).
- [ ] The transcriber exposes a per-call result that includes the final text,
  the temperature that produced it, the compression ratio, the average log
  probability, and a boolean `fallbackExhausted`.
- [ ] `TranscriptionPipeline` consumes that result to decide whether to pass
  the previous chunk's tail tokens as `initial_prompt` for the next chunk.
  When `fallbackExhausted` is true on chunk N, chunk N+1 starts with no
  prompt.
- [ ] `condition_on_previous_text` (i.e. `no_context = false` plus a non-empty
  `initial_prompt`) is enabled by default. The PRD-0001-era deletion
  mitigation (`no_speech_thold = 0.9`, `suppress_blank = false`) is reviewed:
  values are either kept with a written justification or revised against the
  PRD-0004 benchmark.
- [ ] All thresholds and the temperature ladder are defined as named
  constants in `DecodeConfig` with comments citing the upstream OpenAI
  defaults they mirror.
- [ ] `PipelineEventLog` receives: `decoder.attempt(temperature: T, chunk: i)`,
  `decoder.attempt_result(compression: C, avg_logprob: L, accepted: bool)`,
  `decoder.fallback_exhausted(chunk: i)`, and
  `decoder.prompt_passed(tokens: N)` / `decoder.prompt_suppressed(reason)`.
- [ ] Unit tests cover: a configuration that always passes thresholds runs
  exactly one Whisper attempt per chunk; a configuration that fails the
  compression threshold retries up to the ladder length; prompt is suppressed
  after `fallbackExhausted`; default `DecodeConfig` matches a documented spec.
- [ ] The PRD-0004 benchmark suite runs against both the old fixed
  configuration and the new `DecodeConfig` defaults, and the new defaults
  show a measurable WER improvement on at least the clean dataset. The
  measured numbers are recorded in the PR description.
- [ ] No regression in existing `TranscriptionPipeline` /
  `RecordingStateMachine` tests.
