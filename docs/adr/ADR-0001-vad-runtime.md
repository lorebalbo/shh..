# ADR-0001: VAD Inference Runtime

## 1. Status

Accepted

## 2. Context

PRD-0001 requires a Voice Activity Detection stage that runs after capture and
before Whisper. Silero VAD is the model of record, but it ships as an ONNX /
PyTorch artefact and macOS has no first-party ONNX runtime. The epic's
foundational requirements lock the runtime decision here so every downstream
PRD can depend on it.

Three options were considered:

- Core ML conversion of Silero VAD.
- ONNX Runtime via Swift Package Manager.
- A vetted native runtime already present in the project.

## 3. Decision

Use the Silero VAD support that is already built into the vendored
`whisper.cpp` static libraries via its native GGML runtime. The C API
(`whisper_vad_init_from_file_with_params`, `whisper_vad_detect_speech`,
`whisper_vad_n_probs`, `whisper_vad_probs`, `whisper_vad_free`) is declared in
`Vendor/whisper.cpp/include/whisper.h` and the symbols are present in
`Vendor/whisper.cpp/lib/libwhisper.a`. The model weights ship as
`ggml-silero-v5.1.2.bin` (885 KB), bundled in `SHH/Resources/` exactly like the
base Whisper model.

SHH consumes only the raw per-frame speech probabilities
(`whisper_vad_probs`) from this runtime and applies its own hysteresis,
padding, and segment-merging logic in pure Swift (`VADSegmentBuilder`). This
keeps the deterministic decision logic testable without linking the C library
into the unit-test bundle.

## 4. Consequences

- Zero new third-party dependencies, no SPM/CocoaPods/ONNX Runtime, no Core ML
  conversion pipeline to maintain.
- The same GGML/Metal backend already used for transcription powers VAD, so
  GPU acceleration is free and the audio-format contract (16 kHz mono Float32)
  is preserved end to end.
- The VAD model is bundled (885 KB, well under the 5 MB threshold in PRD-0001),
  so no first-run download is required; `ModelManager` still exposes a resolver
  for symmetry with the Whisper model path.
- The hysteresis and padding policy lives in SHH-owned Swift code, not in
  whisper.cpp's `whisper_vad_segments_from_probs`, giving full control over the
  mid-sentence-pause behaviour PRD-0001 specifies and full unit-test coverage.
