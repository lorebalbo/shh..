#!/usr/bin/env bash
# fetch-dataset.sh — Download and prepare a public speech dataset for the
#                    transcription benchmark (PRD-0004). Idempotent: re-running
#                    a fetched dataset verifies its checksum and exits quickly.
#
# Usage:
#   ./scripts/fetch-dataset.sh <dataset-name> [--dry-run]
#
# Registered datasets:
#   librispeech-test-clean   read English speech, clean    (~346 MB)
#   librispeech-test-other   read English speech, harder   (~328 MB)
#   musan                    music/speech/noise corpus     (~11 GB)
#   chime6                   real-world noisy (licence)    (manual download)
#
# The cache root defaults to ~/.cache/shh-benchmarks and is overridable via
# the SHH_BENCHMARK_CACHE environment variable. Nothing is written inside the
# repository.

set -euo pipefail

CACHE_ROOT="${SHH_BENCHMARK_CACHE:-$HOME/.cache/shh-benchmarks}"
DOWNLOAD_DIR="$CACHE_ROOT/downloads"
EXTRACT_DIR="$CACHE_ROOT/raw"
DATASET_DIR="$CACHE_ROOT/datasets"

# Dataset registry. To add a dataset, add one block to dataset_info(). It echoes
#   url<TAB>sha256<TAB>approx_size<TAB>kind
# kind is one of: librispeech, musan, manual. An empty/blank sha256 skips
# checksum verification with a warning.
dataset_info() {
    case "$1" in
        librispeech-test-clean)
            printf '%s\t%s\t%s\t%s' \
                "https://www.openslr.org/resources/12/test-clean.tar.gz" \
                "39fde525e59672dc6d1551919b1478f724438a95aa55f874b576be21967e6c23" \
                "~346 MB" "librispeech" ;;
        librispeech-test-other)
            printf '%s\t%s\t%s\t%s' \
                "https://www.openslr.org/resources/12/test-other.tar.gz" \
                "d09c181bba5cf717b3dee7d4d592af11a3ee3a09e08ae025c5506f6ebe961c29" \
                "~328 MB" "librispeech" ;;
        musan)
            printf '%s\t%s\t%s\t%s' \
                "https://www.openslr.org/resources/17/musan.tar.gz" \
                "" \
                "~11 GB" "musan" ;;
        chime6)
            printf '%s\t%s\t%s\t%s' \
                "https://chimechallenge.org/challenges/chime6/download" \
                "" \
                "~165 GB" "manual" ;;
        *)
            return 1 ;;
    esac
}

REGISTERED="librispeech-test-clean librispeech-test-other musan chime6"

NAME="${1:-}"
DRY_RUN=false
for arg in "${@:2}"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        *) echo "error: unknown argument: $arg" >&2; exit 1 ;;
    esac
done

if [[ -z "$NAME" ]]; then
    echo "usage: $0 <dataset-name> [--dry-run]" >&2
    echo "registered: $REGISTERED" >&2
    exit 1
fi

INFO="$(dataset_info "$NAME")" || {
    echo "error: unknown dataset '$NAME'" >&2
    echo "registered: $REGISTERED" >&2
    exit 1
}

URL="$(printf '%s' "$INFO" | cut -f1)"
EXPECTED_SHA_RAW="$(printf '%s' "$INFO" | cut -f2)"
SIZE="$(printf '%s' "$INFO" | cut -f3)"
KIND="$(printf '%s' "$INFO" | cut -f4)"

if [[ "$DRY_RUN" == true ]]; then
    echo "Dataset:        $NAME"
    echo "Kind:           $KIND"
    echo "Approx. size:   $SIZE"
    echo "Cache root:     $CACHE_ROOT"
    echo "Target manifest: $DATASET_DIR/$NAME/manifest.json"
    exit 0
fi

# Licence-restricted datasets are never auto-downloaded.
if [[ "$KIND" == "manual" ]]; then
    echo "error: '$NAME' is licence-restricted and must be downloaded manually." >&2
    echo "  Download from: $URL" >&2
    echo "  Then extract into: $EXTRACT_DIR/$NAME/" >&2
    echo "  and re-run preparation." >&2
    exit 2
fi

MANIFEST="$DATASET_DIR/$NAME/manifest.json"
if [[ -f "$MANIFEST" ]]; then
    echo "$NAME: already up to date ($MANIFEST)"
    exit 0
fi

mkdir -p "$DOWNLOAD_DIR" "$EXTRACT_DIR" "$DATASET_DIR/$NAME"

ARCHIVE="$DOWNLOAD_DIR/$NAME.tar.gz"
EXPECTED_SHA="${EXPECTED_SHA_RAW// /}"

if [[ ! -f "$ARCHIVE" ]]; then
    echo "Downloading $NAME ($SIZE) from $URL …"
    curl -fL --retry 3 -o "$ARCHIVE.partial" "$URL"
    mv "$ARCHIVE.partial" "$ARCHIVE"
fi

if [[ -n "$EXPECTED_SHA" ]]; then
    echo "Verifying checksum …"
    ACTUAL_SHA="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"
    if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
        echo "error: checksum mismatch for $NAME" >&2
        echo "  expected: $EXPECTED_SHA" >&2
        echo "  actual:   $ACTUAL_SHA" >&2
        exit 3
    fi
else
    echo "warning: no checksum registered for $NAME — skipping verification" >&2
fi

echo "Extracting …"
RAW="$EXTRACT_DIR/$NAME"
mkdir -p "$RAW"
tar -xzf "$ARCHIVE" -C "$RAW"

echo "Building manifest …"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
python3 "$SCRIPT_DIR/benchmark/prepare_manifest.py" \
    --kind "$KIND" \
    --raw "$RAW" \
    --output "$MANIFEST"

echo "$NAME ready: $MANIFEST"
