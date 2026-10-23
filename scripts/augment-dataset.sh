#!/usr/bin/env bash
# augment-dataset.sh — Generate a noise-augmented variant of a prepared source
#                      dataset by mixing each clip with a randomly-chosen noise
#                      sample at one or more target SNR levels. The clean
#                      reference transcripts are preserved so WER is measured
#                      against ground truth, which is the point of the stress
#                      test.
#
# Usage:
#   ./scripts/augment-dataset.sh \
#       --source librispeech-test-clean \
#       --noise  musan \
#       --snr    10 \
#       --output librispeech-clean-musan-10db \
#       [--seed 1234]
#
# --snr accepts a single value or a comma-separated list (e.g. 0,10,20); when a
# list is given, one output dataset is produced per SNR with the level appended
# to --output. Audio is mixed as 16 kHz mono 16-bit WAV.

set -euo pipefail

CACHE_ROOT="${SHH_BENCHMARK_CACHE:-$HOME/.cache/shh-benchmarks}"
DATASET_DIR="$CACHE_ROOT/datasets"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

SOURCE=""
NOISE=""
SNR=""
OUTPUT=""
SEED="0"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --source) SOURCE="$2"; shift 2 ;;
        --noise) NOISE="$2"; shift 2 ;;
        --snr) SNR="$2"; shift 2 ;;
        --output) OUTPUT="$2"; shift 2 ;;
        --seed) SEED="$2"; shift 2 ;;
        *) echo "error: unknown argument: $1" >&2; exit 1 ;;
    esac
done

for required in SOURCE NOISE SNR OUTPUT; do
    if [[ -z "${!required}" ]]; then
        echo "error: --${required,,} is required" >&2
        exit 1
    fi
done

SOURCE_MANIFEST="$DATASET_DIR/$SOURCE/manifest.json"
NOISE_MANIFEST="$DATASET_DIR/$NOISE/manifest.json"
if [[ ! -f "$SOURCE_MANIFEST" ]]; then
    echo "error: source dataset not prepared: $SOURCE_MANIFEST" >&2
    echo "  run: ./scripts/fetch-dataset.sh $SOURCE" >&2
    exit 1
fi
if [[ ! -f "$NOISE_MANIFEST" ]]; then
    echo "error: noise dataset not prepared: $NOISE_MANIFEST" >&2
    echo "  run: ./scripts/fetch-dataset.sh $NOISE" >&2
    exit 1
fi

IFS=',' read -ra SNR_LIST <<< "$SNR"
for snr in "${SNR_LIST[@]}"; do
    if [[ ${#SNR_LIST[@]} -gt 1 ]]; then
        out_name="${OUTPUT}-${snr}db"
    else
        out_name="$OUTPUT"
    fi
    out_dir="$DATASET_DIR/$out_name"
    echo "Augmenting $SOURCE + $NOISE @ ${snr}dB -> $out_name"
    mkdir -p "$out_dir/audio"
    python3 "$SCRIPT_DIR/benchmark/augment_dataset.py" \
        --source-manifest "$SOURCE_MANIFEST" \
        --noise-manifest "$NOISE_MANIFEST" \
        --snr "$snr" \
        --seed "$SEED" \
        --output-dir "$out_dir" \
        --mixer "$SCRIPT_DIR/benchmark/mix_audio.py"
    echo "  -> $out_dir/manifest.json"
done
