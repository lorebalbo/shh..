---
status: Implemented
---
# PRD-0002: VAD-Driven Intelligent Chunking and Stitching

## 1. Problem

Whisper processes audio in fixed 30-second windows internally. When SHH hands
it a long buffer, whisper.cpp slices that buffer on a clock, not on speech
boundaries — so a word that happens to span the 30 s mark gets cut in half,
one half is transcribed in one window, the other half in the next, and
because `no_context = true` (set by PRD-0001's predecessor as a deletion
mitigation) the second window has no idea the first word was mid-utterance.
The result is dropped or mangled words at every 30 s boundary.

PRD-0001 gives us sample-indexed speech segments. We can do far better than
the clock: we can decide *where* to cut the audio for Whisper so cuts only ever
land inside pauses, and we can reassemble the per-cut Whisper outputs into a
single transcript that reads as if the model had seen the whole recording at
once.

## 2. Objective

The system is able to take the VAD segment list from PRD-0001, group those
segments into Whisper-sized chunks that never split a word, transcribe each
chunk independently, and stitch the per-chunk results into one final string
with no duplicated and no dropped tokens at chunk boundaries.

Verifiable outcomes:

- The user is able to dictate a 2-minute monologue containing several natural
  pauses and receive a transcript with no missing or duplicated phrases around
  the implicit chunk seams.
- Every chunk Whisper sees is ≤ 28 s of audio (≤ Whisper's 30 s window with a
  safety margin) and starts/ends inside a VAD-detected pause.
- For recordings shorter than the single-chunk threshold, the system bypasses
  chunking entirely and behaves identically to PRD-0001's single-buffer path
  (no overhead, no behaviour change).

## 3. User Flow

1. The user dictates a long passage with several natural pauses and releases
   the hotkey.
2. `RecordingCoordinator` runs VAD (PRD-0001) and receives a list of speech
   segments covering the full recording.
3. The new `TranscriptionChunker` consumes that segment list and groups
   adjacent segments into chunks, respecting two rules:
   - A chunk's total audio duration (speech + padding) must not exceed the
     configured maximum (e.g. 28 s).
   - A chunk boundary may only fall inside a VAD-detected pause (i.e.
     between segments), never inside a segment.
4. If a single VAD segment is itself longer than the max chunk duration
   (the user spoke continuously for > 28 s without pausing), the chunker
   falls back to cutting that segment on its lowest-energy frame inside the
   acceptable window — a degraded but bounded behaviour, logged as
   `chunker.forced_split`.
5. The chunker emits an ordered list of chunk buffers; `TranscriptionPipeline`
   transcribes each chunk in order through a single shared Whisper context.
6. The stitcher concatenates the per-chunk transcripts with a single space
   separator, trimming whitespace and collapsing repeated punctuation at the
   seams.
7. The user sees the assembled transcript in the overlay exactly as today;
   no chunk seams are visible.
8. Alternative: a chunk's Whisper call returns empty (e.g. VAD let through a
   sub-threshold segment that Whisper considers silence). The stitcher
   silently skips that chunk's output and logs `chunker.empty_chunk_output`.
9. Alternative: only one chunk is produced (recording is short). The chunker
   passes the buffer through unchanged and the stitcher is a no-op.

## 4. Acceptance Criteria

- [ ] A new `TranscriptionChunker` type lives in `SHH/Managers/` and exposes a
  method that takes `(buffer: [Float], segments: [SpeechSegment])` and returns
  an ordered `[AudioChunk]` where each chunk carries its own `[Float]` slice
  and its sample-range in the original buffer.
- [ ] No chunk exceeds the configured max duration (default 28 s, defined as
  a named constant).
- [ ] No chunk boundary falls inside a VAD speech segment unless a single
  segment exceeds the max duration, in which case the chunker performs a
  forced split at the lowest-RMS frame in the allowed window and emits a
  `chunker.forced_split` event with the chosen sample index.
- [ ] `TranscriptionPipeline.transcribe` is refactored to: run VAD, run the
  chunker, transcribe each chunk via the existing `WhisperTranscriber`
  instance, and return the stitched string. Public method signature is
  preserved so call sites in `RecordingCoordinator` need no changes.
- [ ] A separate `TranscriptStitcher` (or private helper) joins per-chunk
  outputs with a single space, trims each piece, and collapses doubled
  whitespace and doubled terminal punctuation at the seams.
- [ ] Single-chunk recordings (total audio ≤ max chunk duration) take the
  same code path that PRD-0001 leaves in place — no extra Whisper invocation,
  no measurable overhead vs. PRD-0001 baseline.
- [ ] `PipelineEventLog` receives: `chunker.planned(count: N, total_ms: X)`,
  one `chunker.chunk_completed(index: i, ms: Y)` per chunk,
  `chunker.forced_split`, `chunker.empty_chunk_output`, and
  `chunker.stitched(final_chars: Z)`.
- [ ] Unit tests cover: zero segments → empty transcript, no Whisper call;
  one short segment → one chunk, single Whisper call; many short segments
  fitting in one chunk → one chunk; many segments needing two chunks →
  exactly two chunks with a boundary inside a pause; one giant segment
  exceeding max duration → forced split with a logged event.
- [ ] An integration test feeds a synthetic 60 s buffer (e.g.
  speech-pause-speech-pause-speech) through the full pipeline and asserts
  the stitched transcript contains every expected phrase, in order, with no
  duplicates.
- [ ] No regression in PRD-0001's VAD tests or in the existing
  `RecordingStateMachine` tests.
