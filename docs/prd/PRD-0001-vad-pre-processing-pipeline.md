---
status: Implemented
---
# PRD-0001: VAD Pre-processing Pipeline

## 1. Problem

`AudioCaptureManager` hands `TranscriptionPipeline` the raw 16 kHz mono buffer
from the moment the user presses the dictation hotkey to the moment they
release it. That buffer is full of silence before the user starts speaking,
silence after they finish, mid-utterance pauses while they think, and
non-speech noise (keyboard clicks, HVAC, breath). Whisper has to make sense of
all of it in 30-second windows, and when a window is dominated by silence or
noise, the `no_speech_thold` gate fires and the whole window's text is
discarded — the user's words are silently deleted. The current mitigations in
`WhisperTranscriber` (raising `no_speech_thold` to 0.9, disabling
`suppress_blank`, forcing `no_context = true`) work around the symptom but do
not solve the root cause: Whisper is being asked to transcribe audio that is
mostly not speech.

SHH users dictating multi-sentence thoughts experience this as dropped words
and missing sentences, especially in noisier environments where the noise
itself crosses Whisper's internal speech-probability thresholds inconsistently.

## 2. Objective

The system is able to receive a raw recorded buffer and produce, before any
Whisper invocation, a list of sample-indexed speech segments with all leading,
trailing, and inter-speech silence and non-speech removed. Downstream stages
(chunker, transcriber) operate exclusively on speech-bearing audio, so
Whisper's silence-driven failure modes can no longer cause deletions.

Verifiable outcomes:

- For any input buffer, the pipeline can return both a filtered speech-only
  buffer and the list of `(startSample, endSample)` speech segments that
  produced it.
- On a recording that is 80% silence (e.g. a 30 s buffer containing 6 s of
  speech), the buffer passed to Whisper is ≤ 8 s long (speech + minimal
  padding) instead of 30 s.
- The pipeline runs ≤ 50 ms per second of input audio on an M-series Mac
  (i.e. ≥ 20× real-time), so it does not visibly extend the wait between
  hotkey release and transcript appearance.

## 3. User Flow

1. The user presses the dictation hotkey and starts speaking.
2. The user pauses mid-sentence, resumes, finishes their thought, and releases
   the hotkey.
3. `RecordingCoordinator` receives the raw PCM buffer from
   `AudioCaptureManager` as it does today.
4. Before invoking `TranscriptionPipeline.transcribe`, the coordinator runs
   the buffer through the new `VADProcessor`, which:
   - Slides Silero VAD over the buffer in fixed-size frames.
   - Emits a list of speech segments with hysteresis (a short pause inside a
     sentence does not split a segment; a long pause does).
   - Returns the filtered buffer and the segment list.
5. `TranscriptionPipeline` receives the filtered buffer and transcribes it
   exactly as it does today (PRD-0002 will later replace this with chunked
   transcription).
6. The user sees the resulting text in the overlay; no UX change is visible.
7. Alternative: the buffer contains zero detected speech (the user pressed
   the hotkey and released it without speaking). The pipeline short-circuits,
   emits an empty transcript, and `PipelineEventLog` records a
   `vad.no_speech_detected` event. The overlay shows the existing
   "no audio" state.
8. Alternative: VAD model fails to load at startup (missing weights, runtime
   error). The pipeline logs `vad.unavailable` and falls back to passing the
   unfiltered buffer to Whisper — degraded behaviour, never a hard crash, and
   never a blocked recording.

## 4. Acceptance Criteria

- [ ] A new `VADProcessor` type lives in `SHH/Managers/` and exposes a single
  method that takes `[Float]` at 16 kHz mono and returns
  `(filtered: [Float], segments: [SpeechSegment])` where `SpeechSegment` holds
  sample-indexed `start` and `end`.
- [ ] Silero VAD (or the locked-in equivalent — Core ML conversion, ONNX
  Runtime via SPM, or a vetted Swift port) is integrated; the chosen runtime
  decision is recorded as an ADR before the implementation PR merges.
- [ ] The VAD model file is either bundled with the app (if ≤ 5 MB after
  compression) or downloaded on first run by `ModelManager` using the same
  cache directory pattern as the Whisper models.
- [ ] `VADProcessor` applies hysteresis: speech onset requires N consecutive
  speech-positive frames; speech offset requires M consecutive speech-negative
  frames. N and M are documented constants tuned so that mid-sentence pauses
  ≤ 600 ms do not split a segment.
- [ ] Each returned segment is padded by a small fixed margin (e.g. 100 ms on
  each side, clipped to buffer bounds) so Whisper sees a clean attack and
  release rather than a hard-clipped edge.
- [ ] `RecordingCoordinator` invokes `VADProcessor` between capture and
  transcription. Existing short-utterance behaviour is preserved: a 2 s buffer
  with continuous speech is unchanged in length after VAD (within ± padding).
- [ ] `PipelineEventLog` receives at minimum: `vad.started`,
  `vad.completed(segments: N, kept_ms: X, dropped_ms: Y)`,
  `vad.no_speech_detected`, and `vad.unavailable`.
- [ ] If VAD fails (model load error, runtime error), the pipeline logs the
  failure and continues with the unfiltered buffer instead of throwing.
- [ ] Unit tests cover: pure-silence buffer → empty segments; pure-speech
  buffer → single segment spanning the buffer; speech-pause-speech buffer
  with a short pause → single segment; speech-pause-speech buffer with a long
  pause → two segments; corrupted/short buffer (< one VAD frame) → returns
  input unchanged with no crash.
- [ ] Performance test confirms VAD processes ≥ 20× real-time on M-series Macs
  (≤ 50 ms per 1 s of audio).
- [ ] No regression in existing `TranscriptionPipeline` or
  `RecordingStateMachine` tests.
