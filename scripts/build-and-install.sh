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

# ── 2. Generate app icon assets ──────────────────────────────────────────────
echo "[2/5] Generating app icon assets..."
ICON_DIR="$PROJECT_DIR/SHH/Assets.xcassets/AppIcon.appiconset"
swift "$SCRIPT_DIR/generate-icon.swift" "$ICON_DIR"
echo ""

# ── 3. Generate Xcode project from project.yml ────────────────────────────────
echo "[3/5] Generating Xcode project with xcodegen..."
cd "$PROJECT_DIR"
xcodegen generate --spec project.yml
echo ""

# ── 4. Build the app ──────────────────────────────────────────────────────────
echo "[4/5] Building $APP_NAME..."
rm -rf "$BUILD_DIR"
if command -v xcpretty &>/dev/null; then
    xcodebuild \
        -scheme "$SCHEME" \
        -project "$APP_NAME.xcodeproj" \
        -configuration Release \
        -destination 'platform=macOS,arch=arm64' \
        -derivedDataPath "$BUILD_DIR" \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        AD_HOC_CODE_SIGNING_ALLOWED=YES \
        2>&1 | xcpretty
else
    xcodebuild \
        -scheme "$SCHEME" \
        -project "$APP_NAME.xcodeproj" \
        -configuration Release \
        -destination 'platform=macOS,arch=arm64' \
        -derivedDataPath "$BUILD_DIR" \
        CODE_SIGN_STYLE=Manual \
        CODE_SIGN_IDENTITY="-" \
        CODE_SIGNING_REQUIRED=NO \
        CODE_SIGNING_ALLOWED=NO \
        AD_HOC_CODE_SIGNING_ALLOWED=YES
fi
echo ""

# ── 5. Install to /Applications ───────────────────────────────────────────────
echo "[5/5] Installing $APP_NAME.app to /Applications..."
APP_PATH=$(find "$BUILD_DIR" -name "${APP_NAME}.app" -maxdepth 6 | head -n 1)

if [ -z "$APP_PATH" ]; then
    echo "Error: ${APP_NAME}.app not found in build output."
    exit 1
fi

# Overwrite previous installation (cp -R overwrites existing contents)
cp -Rf "$APP_PATH" /Applications/

# Refresh LaunchServices so macOS picks up the correct name and icon immediately
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
    -f "/Applications/${APP_NAME}.app" 2>/dev/null || true
echo ""
echo "Done! ${APP_NAME}.app installed in /Applications."
