#!/usr/bin/env bash
# uninstall.sh — Removes every copy of SHH.app from this Mac, together with
#                its associated caches, preferences, and app-support data.
#
# Usage:
#   ./scripts/uninstall.sh            # interactive (asks before deleting)
#   ./scripts/uninstall.sh --yes      # non-interactive (skip confirmation)

set -euo pipefail

APP_NAME="SHH"
BUNDLE_ID="com.shh.voice-utility"
YES=false
[[ "${1-}" == "--yes" ]] && YES=true

# ── Helpers ──────────────────────────────────────────────────────────────────

red()    { printf '\033[0;31m%s\033[0m\n' "$*"; }
green()  { printf '\033[0;32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[0;33m%s\033[0m\n' "$*"; }
bold()   { printf '\033[1m%s\033[0m\n' "$*"; }

confirm() {
    if $YES; then return 0; fi
    printf '%s [y/N] ' "$1"
    read -r answer
    [[ "$answer" =~ ^[Yy]$ ]]
}

remove() {
    local path="$1"
    if [[ -e "$path" || -L "$path" ]]; then
        rm -rf "$path"
        echo "  removed: $path"
    fi
}

# ── 1. Find all .app bundles ──────────────────────────────────────────────────

bold "==> $APP_NAME — Uninstaller"
echo ""

echo "Searching for ${APP_NAME}.app installations…"

APP_LOCATIONS=(
    "/Applications/${APP_NAME}.app"
    "$HOME/Applications/${APP_NAME}.app"
    "$HOME/Desktop/${APP_NAME}.app"
    "$HOME/Downloads/${APP_NAME}.app"
)

# Also run a broader Spotlight search (mdfind is fast and non-blocking)
while IFS= read -r path; do
    APP_LOCATIONS+=("$path")
done < <(mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null || true)

# De-duplicate (bash 3 compatible)
FOUND_APPS=()
for path in "${APP_LOCATIONS[@]}"; do
    [[ -d "$path" ]] || continue
    # Check if already in FOUND_APPS
    already=false
    for existing in "${FOUND_APPS[@]-}"; do
        [[ "$existing" == "$path" ]] && already=true && break
    done
    $already || FOUND_APPS+=("$path")
done

# ── 2. Collect associated data ────────────────────────────────────────────────

DATA_PATHS=(
    "$HOME/Library/Application Support/${APP_NAME}"
    "$HOME/Library/Application Support/${BUNDLE_ID}"
    "$HOME/Library/Preferences/${BUNDLE_ID}.plist"
    "$HOME/Library/Caches/${BUNDLE_ID}"
    "$HOME/Library/Caches/${APP_NAME}"
    "$HOME/Library/Logs/${APP_NAME}"
    "$HOME/Library/Logs/${BUNDLE_ID}"
    "$HOME/Library/Saved Application State/${BUNDLE_ID}.savedState"
    "$HOME/Library/HTTPStorages/${BUNDLE_ID}"
    "$HOME/Library/Containers/${BUNDLE_ID}"
    "$HOME/Library/WebKit/${BUNDLE_ID}"
)

FOUND_DATA=()
for path in "${DATA_PATHS[@]}"; do
    [[ -e "$path" ]] && FOUND_DATA+=("$path")
done

# ── 3. Report ─────────────────────────────────────────────────────────────────

if [[ ${#FOUND_APPS[@]} -eq 0 && ${#FOUND_DATA[@]} -eq 0 ]]; then
    green "Nothing to remove — ${APP_NAME} does not appear to be installed."
    exit 0
fi

if [[ ${#FOUND_APPS[@]} -gt 0 ]]; then
    echo ""
    yellow "App bundles found (${#FOUND_APPS[@]}):"
    for p in "${FOUND_APPS[@]}"; do echo "  $p"; done
fi

if [[ ${#FOUND_DATA[@]} -gt 0 ]]; then
    echo ""
    yellow "Associated data found (${#FOUND_DATA[@]}):"
    for p in "${FOUND_DATA[@]}"; do echo "  $p"; done
fi

echo ""

# ── 4. Confirm & delete ───────────────────────────────────────────────────────

if ! confirm "Delete all of the above?"; then
    echo "Aborted — nothing was deleted."
    exit 0
fi

echo ""

# Quit the app gracefully before removing it (ignore errors if not running)
osascript -e "tell application \"${APP_NAME}\" to quit" 2>/dev/null || true
sleep 1

for p in "${FOUND_APPS[@]}" "${FOUND_DATA[@]}"; do
    remove "$p"
done

# Unregister from LaunchServices so the app no longer appears in Spotlight / Open With menus
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister \
    -u "/Applications/${APP_NAME}.app" 2>/dev/null || true

echo ""
green "Done! All copies of ${APP_NAME} have been removed."
