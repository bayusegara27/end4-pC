#!/usr/bin/env bash

# Keep the shell in sync with the wallpaper linux-wallpaperengine is showing.
#
# wpe-manager has no post-change hook, so this is driven by a watcher on its
# engine.json — the concrete "what is running on each screen" state it rewrites
# on every switch and on every playlist rotation. Two things are updated here:
#
#   1. background.wallpaperPath, so the parts of the shell that render the
#      wallpaper themselves (lock screen, user card) stop showing a stale image.
#   2. the generated palette, by handing the work to switchwall.sh.
#
# Safe to run by hand at any time; it is a no-op when nothing has changed.
#
# Usage: wpe-colorsync.sh [--force] [--wait]

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"
STILL_DIR="$XDG_STATE_HOME/quickshell/user/generated/wallpaper/wpe"
CURRENT_ID_FILE="$STILL_DIR/current-id"
LOCK_FILE="$STILL_DIR/.sync.lock"
LOG_FILE="$STILL_DIR/colorsync.log"
# Kept separate: switchwall.sh leaves a kde-material-you-colors daemon holding
# its stdout, which would drown this script's own entries.
SWITCHWALL_LOG="$STILL_DIR/switchwall.log"

# wpe-manager overlaps the outgoing and incoming wallpaper (overlap_ms) and
# writes engine.json with a plain truncate-and-write, so give the swap a moment
# to settle before reading it.
SETTLE_SECONDS="${WPE_COLORSYNC_SETTLE:-2}"

force=""
wait_for_backend=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --force) force="1"; shift ;;
        --wait)  wait_for_backend="1"; shift ;;
        *)       shift ;;
    esac
done

mkdir -p "$STILL_DIR"

trim_log() {
    # Keep a log from growing without bound.
    local file="$1"
    if [[ -f "$file" && $(stat -c %s "$file" 2>/dev/null || echo 0) -gt 65536 ]]; then
        tail -n 100 "$file" > "$file.tmp" && mv "$file.tmp" "$file"
    fi
}

log() {
    trim_log "$LOG_FILE"
    echo "$(date '+%Y-%m-%d %H:%M:%S')  $*" >> "$LOG_FILE"
}

# Used at session start, where the backend may not be up yet. Deliberately
# ahead of the lock so a long wait never blocks a real wallpaper change.
if [[ -n "$wait_for_backend" ]]; then
    for _ in $(seq 1 60); do
        pgrep -f linux-wallpaperengine >/dev/null 2>&1 && break
        sleep 1
    done
fi

# Only one sync at a time: a playlist rotation can fire the watcher again while
# the previous run is still generating colors.
exec 9>"$LOCK_FILE"
flock -w 60 9 || { log "busy, skipped"; exit 0; }

sleep "$SETTLE_SECONDS"

still="$("$SCRIPT_DIR/wpe-source.sh" 2>/dev/null)"
if [[ -z "$still" || ! -f "$still" ]]; then
    # No live wallpaper (or it could not be resolved). Leave the current theme
    # alone rather than guessing.
    exit 0
fi
wallpaper_id="$(basename "$still" .jpg)"

configured_path=""
if [[ -f "$SHELL_CONFIG_FILE" ]]; then
    configured_path="$(jq -r '.background.wallpaperPath // ""' "$SHELL_CONFIG_FILE" 2>/dev/null)"
fi
last_id="$(cat "$CURRENT_ID_FILE" 2>/dev/null)"

if [[ -z "$force" && "$last_id" == "$wallpaper_id" && "$configured_path" == "$still" ]]; then
    exit 0
fi

# Point the shell at the live wallpaper's still. switchwall.sh only rewrites
# this when it actually switches a wallpaper, and it must not switch anything
# here — linux-wallpaperengine owns the background.
if [[ -f "$SHELL_CONFIG_FILE" ]]; then
    # Remember the last wallpaper the user actually chose, so turning the live
    # wallpaper off can restore it. A Workshop preview still is far too small
    # to serve as a real wallpaper.
    if [[ -n "$configured_path" && "$configured_path" != "$STILL_DIR"/* ]]; then
        echo "$configured_path" > "$STILL_DIR/previous-shell-wallpaper"
    fi
    if jq --arg path "$still" '.background.wallpaperPath = $path' \
            "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" 2>/dev/null; then
        mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE"
    else
        rm -f "$SHELL_CONFIG_FILE.tmp"
        log "failed to update wallpaperPath, colors only"
    fi
fi

# switchwall.sh resolves the live wallpaper itself and regenerates in
# colors-only mode, so the running wallpaper is never disturbed. The light/dark
# mode and any pinned accent colour stay under its control.
# 9>&- keeps the lock out of switchwall.sh's children: it leaves a
# kde-material-you-colors daemon running, which would otherwise hold the lock
# open long after this script exits and stall every later sync.
trim_log "$SWITCHWALL_LOG"
if "$SCRIPT_DIR/switchwall.sh" --noswitch >>"$SWITCHWALL_LOG" 2>&1 9>&-; then
    echo "$wallpaper_id" > "$CURRENT_ID_FILE"
    log "synced to $wallpaper_id"
else
    log "switchwall.sh failed for $wallpaper_id"
    exit 1
fi
