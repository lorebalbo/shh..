#!/usr/bin/env bash
# distribute.sh — Builds SHH and packages it as a shareable DMG.
#
# Usage:
#   ./scripts/distribute.sh
#
# Output: SHH-<version>.dmg in the project root.
#
# Prerequisites: xcodegen (brew install xcodegen), Xcode command-line tools
#
# NOTE: This build is not notarized with Apple. Recipients must right-click
#       "SHH.app" and choose "Open" the first time to bypass Gatekeeper.
#       The app requires macOS 14.0+ and Apple Silicon (M-series Mac).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_DIR/build"
APP_NAME="SHH"
SCHEME="SHH"

# Read version from Info.plist
VERSION=$(defaults read "$PROJECT_DIR/SHH/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.0")
DMG_NAME="${APP_NAME}-${VERSION}.dmg"
DMG_PATH="$PROJECT_DIR/$DMG_NAME"

echo "==> SHH — Package for Distribution (v${VERSION})"
echo ""

# ── 1. Download Whisper model if needed ───────────────────────────────────────
echo "[1/5] Checking Whisper model..."
"$SCRIPT_DIR/download-model.sh"
echo ""

# ── 2. Generate app icon assets ───────────────────────────────────────────────
echo "[2/5] Generating app icon..."
ICON_DIR="$PROJECT_DIR/SHH/Assets.xcassets/AppIcon.appiconset"
swift "$SCRIPT_DIR/generate-icon.swift" "$ICON_DIR"
echo ""

# ── 3. Generate Xcode project from project.yml ────────────────────────────────
echo "[3/5] Generating Xcode project..."
cd "$PROJECT_DIR"
xcodegen generate --spec project.yml
echo ""

# ── 4. Build Release ──────────────────────────────────────────────────────────
echo "[4/5] Building Release..."
rm -rf "$BUILD_DIR"
BUILD_ARGS=(
    -scheme "$SCHEME"
    -project "$APP_NAME.xcodeproj"
    -configuration Release
    -destination 'platform=macOS,arch=arm64'
    -derivedDataPath "$BUILD_DIR"
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="-"
    CODE_SIGNING_REQUIRED=NO
    CODE_SIGNING_ALLOWED=NO
    AD_HOC_CODE_SIGNING_ALLOWED=YES
)
if command -v xcpretty &>/dev/null; then
    xcodebuild "${BUILD_ARGS[@]}" 2>&1 | xcpretty
else
    xcodebuild "${BUILD_ARGS[@]}"
fi
echo ""

# ── 5. Create DMG ─────────────────────────────────────────────────────────────
echo "[5/5] Creating DMG..."
APP_PATH=$(find "$BUILD_DIR" -name "${APP_NAME}.app" -maxdepth 6 | head -n 1)

if [ -z "$APP_PATH" ]; then
    echo "Error: ${APP_NAME}.app not found in build output."
    exit 1
fi

# Staging folder with the app + Applications symlink for drag-install UX
STAGING="$BUILD_DIR/dmg-staging"
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

# Remove any stale DMG from a previous run
rm -f "$DMG_PATH"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

echo ""
echo "============================================================"
echo "  Done!  ${DMG_NAME}"
echo "  Path:  ${DMG_PATH}"
echo "============================================================"
echo ""
echo "How to share:"
echo "  Upload ${DMG_NAME} to iCloud Drive, Google Drive, WeTransfer,"
echo "  or any file-sharing service and send the link to your friends."
echo ""
echo "What your friends need to do:"
echo "  1. Open ${DMG_NAME}"
echo "  2. Drag SHH.app into the Applications folder shown in the DMG"
echo "  3. Eject the DMG"
echo "  4. Find SHH in Applications, RIGHT-CLICK it, and choose 'Open'"
echo "     (required only the first time — bypasses macOS Gatekeeper)"
echo ""
echo "System requirements: macOS 14 Sonoma or later, Apple Silicon (M-series)"
