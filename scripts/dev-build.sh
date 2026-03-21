#!/usr/bin/env bash
# dev-build.sh — Fast development build. Skips model download, xcodegen, and
#                /Applications install. Builds Debug and runs the app in place.
#
# Usage:
#   ./scripts/dev-build.sh [--regen]
#
#   --regen   Force xcodegen regeneration (use when project.yml has changed)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="SHH"
SCHEME="SHH"
REGEN=false

for arg in "$@"; do
    case $arg in
        --regen) REGEN=true ;;
        *) echo "Unknown argument: $arg"; exit 1 ;;
    esac
done

echo "==> SHH — Dev Build (Debug)"
echo ""

# ── 1. Regenerate Xcode project only when requested ───────────────────────────
if [ "$REGEN" = true ]; then
    echo "[1/2] Regenerating Xcode project with xcodegen..."
    cd "$PROJECT_DIR"
    xcodegen generate --spec project.yml
    echo ""
else
    echo "[1/2] Skipping xcodegen (pass --regen if project.yml changed)"
    echo ""
fi

# ── 2. Build Debug ─────────────────────────────────────────────────────────────
echo "[2/2] Building $APP_NAME (Debug)..."
cd "$PROJECT_DIR"
if command -v xcpretty &>/dev/null; then
    set -o pipefail
    xcodebuild \
        -scheme "$SCHEME" \
        -project "$APP_NAME.xcodeproj" \
        -configuration Debug \
        -derivedDataPath "$BUILD_DIR" \
        CODE_SIGN_IDENTITY="-" \
        AD_HOC_CODE_SIGNING_ALLOWED=YES \
        | xcpretty
else
    xcodebuild \
        -scheme "$SCHEME" \
        -project "$APP_NAME.xcodeproj" \
        -configuration Debug \
        -derivedDataPath "$BUILD_DIR" \
        CODE_SIGN_IDENTITY="-" \
        AD_HOC_CODE_SIGNING_ALLOWED=YES
fi
echo ""

# ── 3. Launch the app ──────────────────────────────────────────────────────────
APP_PATH=$(find "$BUILD_DIR" -name "${APP_NAME}.app" -maxdepth 6 | head -n 1)

if [ -z "$APP_PATH" ]; then
    echo "Error: ${APP_NAME}.app not found in build output."
    exit 1
fi

echo "Build succeeded: $APP_PATH"
echo "Launching..."
open "$APP_PATH"
