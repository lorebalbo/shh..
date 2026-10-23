#!/usr/bin/env bash
# benchmark-transcription.sh — Build and run the Whisper transcription benchmark
#                             CLI over a labelled dataset manifest, producing a
#                             timestamped JSON report under build/benchmarks/.
#
# Usage:
#   ./scripts/benchmark-transcription.sh \
#       --model    /path/to/ggml-model.bin \
#       --vad-model /path/to/ggml-silero.bin \
#       --manifest /path/to/manifest.json \
#       [--language auto] [--output report.json]
#
#   Compare two reports (exits non-zero if WER regresses > 0.5pp):
#   ./scripts/benchmark-transcription.sh --compare baseline.json candidate.json
#
# The manifest is a JSON array of { "audio": "rel/or/abs.wav", "reference": "..." }.
# Relative audio paths are resolved against the manifest's own directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
SCHEME="benchmark"

cd "$PROJECT_DIR"

if [[ "${1:-}" != "--compare" ]]; then
    if ! command -v xcodegen >/dev/null 2>&1; then
        echo "error: xcodegen not found (brew install xcodegen)" >&2
        exit 1
    fi
    xcodegen generate >/dev/null
fi

echo "Building benchmark CLI…"
DERIVED="$PROJECT_DIR/build/benchmark-derived"
xcodebuild build \
    -project "$PROJECT_DIR/SHH.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED" \
    >/dev/null

BIN="$DERIVED/Build/Products/Debug/shh-benchmark"
if [[ ! -x "$BIN" ]]; then
    echo "error: benchmark binary not found at $BIN" >&2
    exit 1
fi

echo "Running benchmark…"
exec "$BIN" "$@"
