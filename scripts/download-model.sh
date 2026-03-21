#!/usr/bin/env bash
set -euo pipefail

# download-model.sh — Downloads the whisper.cpp base model for bundling in the app.
#
# Usage:
#   ./scripts/download-model.sh
#
# The model will be placed in SHH/Resources/ggml-base.bin

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
RESOURCES_DIR="$PROJECT_DIR/SHH/Resources"
MODEL_FILE="$RESOURCES_DIR/ggml-base.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.bin"

if [ -f "$MODEL_FILE" ]; then
    echo "Model already exists at $MODEL_FILE"
    echo "Size: $(du -h "$MODEL_FILE" | cut -f1)"
    exit 0
fi

mkdir -p "$RESOURCES_DIR"

echo "Downloading whisper.cpp base model (~142 MB)..."
echo "URL: $MODEL_URL"
echo "Destination: $MODEL_FILE"

curl -L --progress-bar -o "$MODEL_FILE" "$MODEL_URL"

if [ -f "$MODEL_FILE" ]; then
    echo "Download complete. Size: $(du -h "$MODEL_FILE" | cut -f1)"
else
    echo "Error: Download failed."
    exit 1
fi
