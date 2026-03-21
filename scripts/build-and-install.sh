#!/usr/bin/env bash
# build-and-install.sh — Builds SHH and installs it in /Applications.
#
# Usage:
#   ./scripts/build-and-install.sh
#
# Prerequisites: xcodegen (brew install xcodegen), Xcode command-line tools

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="SHH"
SCHEME="SHH"

echo "==> SHH — Build & Install"
echo ""

# ── 1. Download Whisper model if needed ────────────────────────────────────────
echo "[1/4] Checking Whisper model..."
"$SCRIPT_DIR/download-model.sh"
echo ""

# ── 2. Generate Xcode project from project.yml ────────────────────────────────
echo "[2/4] Generating Xcode project with xcodegen..."
cd "$PROJECT_DIR"
xcodegen generate --spec project.yml
echo ""

# ── 3. Build the app ──────────────────────────────────────────────────────────
echo "[3/4] Building $APP_NAME..."
rm -rf "$BUILD_DIR"
xcodebuild \
    -scheme "$SCHEME" \
    -project "$APP_NAME.xcodeproj" \
    -configuration Release \
    -derivedDataPath "$BUILD_DIR" \
    CODE_SIGN_IDENTITY="-" \
    AD_HOC_CODE_SIGNING_ALLOWED=YES \
    | xcpretty 2>/dev/null || cat  # fall back to raw output if xcpretty is absent
echo ""

# ── 4. Install to /Applications ───────────────────────────────────────────────
echo "[4/4] Installing $APP_NAME.app to /Applications..."
APP_PATH=$(find "$BUILD_DIR" -name "${APP_NAME}.app" -maxdepth 6 | head -n 1)

if [ -z "$APP_PATH" ]; then
    echo "Error: ${APP_NAME}.app not found in build output."
    exit 1
fi

# Overwrite previous installation (cp -R overwrites existing contents)
cp -Rf "$APP_PATH" /Applications/
echo ""
echo "Done! ${APP_NAME}.app installed in /Applications."
