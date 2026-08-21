#!/usr/bin/env bash

# Decide which component owns the desktop background, and enforce it.
#
# Two providers can draw a wallpaper on this setup and they do not know about
# each other, so without a single authority they stack: two backends rendering
# at once, two rotation timers, and colorgen guessing which one to read.
#
#   shell           quickshell draws the wallpaper itself (static images, and
#                   videos via mpvpaper). switchwall.sh owns it.
#   wallpaperengine linux-wallpaperengine draws it, managed by wpe-manager.
#                   The shell's own wallpaper layer stays hidden behind it.
#
# Usage:
#   wallpaper-provider.sh get
#   wallpaper-provider.sh set <shell|wallpaperengine>
#   wallpaper-provider.sh apply          enforce the stored provider (idempotent)

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHELL_CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"
WPE_ENGINE_FILE="$XDG_CONFIG_HOME/wpe-manager/engine.json"
STILL_DIR="$XDG_STATE_HOME/quickshell/user/generated/wallpaper/wpe"
# The wallpaper the shell should go back to when the live wallpaper is turned
# off — a Workshop preview still is far too small to use as a real wallpaper.
PREVIOUS_WALLPAPER_FILE="$STILL_DIR/previous-shell-wallpaper"

# Process lookup is done on argv tokens rather than with `pgrep -f`, which
# matches any command line that merely mentions the name — a terminal running
# one of these scripts would be killed along with the real thing.
argv_tokens() {
    [[ -r "/proc/$1/cmdline" ]] || return 1
    tr '\0' '\n' < "/proc/$1/cmdline"
}

# pids of the wallpaper backend: argv[0] is the binary itself.
backend_pids() {
    local pid argv0
    for pid in $(pgrep -f linux-wallpaperengine 2>/dev/null); do
        argv0="$(argv_tokens "$pid" | head -1)" || continue
        [[ "$argv0" == *[[:space:]]* ]] && continue
        [[ "$(basename -- "$argv0")" == "linux-wallpaperengine" ]] && echo "$pid"
    done
}

# pids of wpe-manager, as an installed entry point (python /usr/bin/wpe-manager)
# or as `python -m wpe_manager`.
manager_pids() {
    local pid token previous
    for pid in $(pgrep -f "wpe.manager" 2>/dev/null); do
        previous=""
        while IFS= read -r token; do
            if [[ "$token" != *[[:space:]]* ]] \
                && { [[ "$(basename -- "$token")" == "wpe-manager" ]] \
                    || { [[ "$previous" == "-m" && "$token" == "wpe_manager" ]]; }; }; then
                echo "$pid"
                break
            fi
            previous="$token"
        done < <(argv_tokens "$pid" 2>/dev/null)
    done
}

kill_pids() {
    local pid
    while read -r pid; do
        [[ "$pid" =~ ^[0-9]+$ ]] && kill "$pid" 2>/dev/null
    done
}

get_provider() {
    local value=""
    [[ -f "$SHELL_CONFIG_FILE" ]] && \
        value="$(jq -r '.background.provider // ""' "$SHELL_CONFIG_FILE" 2>/dev/null)"
    echo "$value"
}

set_config_string() {
    local key="$1" value="$2"
    [[ -f "$SHELL_CONFIG_FILE" ]] || return 1
    jq --arg v "$value" "$key = \$v" "$SHELL_CONFIG_FILE" > "$SHELL_CONFIG_FILE.tmp" \
        && mv "$SHELL_CONFIG_FILE.tmp" "$SHELL_CONFIG_FILE" \
        || { rm -f "$SHELL_CONFIG_FILE.tmp"; return 1; }
}

manager_running() {
    [[ -n "$(manager_pids)" ]]
}

backend_running() {
    [[ -n "$(backend_pids)" ]]
}

start_wallpaperengine() {
    command -v wpe-manager >/dev/null 2>&1 || {
        echo "wpe-manager is not installed" >&2
        return 1
    }
    # --daemon starts hidden in the tray and re-applies the saved assignments,
    # so the wallpaper that was last in use comes back. It is single-instance,
    # so this is safe to call when one is already running.
    setsid wpe-manager --daemon >/dev/null 2>&1 < /dev/null &
    disown 2>/dev/null || true
}

stop_wallpaperengine() {
    # Order matters: the manager owns the backends and would restart them, so
    # it has to go first.
    manager_pids | kill_pids

    # Clear the concrete state so wpe-manager does not believe those processes
    # are still alive. Its *desired* assignments live in state.json and are
    # deliberately left untouched — that is what lets --daemon restore
    # everything when the provider is switched back.
    [[ -f "$WPE_ENGINE_FILE" ]] && echo '{}' > "$WPE_ENGINE_FILE"

    # Covers both what wpe-manager started and anything started outside it,
    # which never appears in engine.json.
    backend_pids | kill_pids
}

restore_shell_wallpaper() {
    local previous=""
    [[ -f "$PREVIOUS_WALLPAPER_FILE" ]] && previous="$(cat "$PREVIOUS_WALLPAPER_FILE")"

    local current=""
    [[ -f "$SHELL_CONFIG_FILE" ]] && \
        current="$(jq -r '.background.wallpaperPath // ""' "$SHELL_CONFIG_FILE" 2>/dev/null)"

    # Only step in when the stored path is a live wallpaper still; anything the
    # user picked themselves is left alone.
    if [[ "$current" == "$STILL_DIR"/* && -n "$previous" && -f "$previous" ]]; then
        set_config_string '.background.wallpaperPath' "$previous"
    fi

    "$SCRIPT_DIR/switchwall.sh" --noswitch >/dev/null 2>&1 &
}

apply_provider() {
    local provider="$1"
    case "$provider" in
        wallpaperengine)
            manager_running || start_wallpaperengine
            ;;
        shell)
            if manager_running || backend_running; then
                stop_wallpaperengine
                restore_shell_wallpaper
            fi
            ;;
        *)
            # No explicit choice stored: leave both alone. wpe-source.sh falls
            # back to detecting whatever is actually running.
            ;;
    esac
}

case "${1:-}" in
    get)
        get_provider
        ;;
    set)
        new_provider="${2:-}"
        case "$new_provider" in
            shell|wallpaperengine) ;;
            *)
                echo "Usage: $(basename "$0") set <shell|wallpaperengine>" >&2
                exit 1
                ;;
        esac
        set_config_string '.background.provider' "$new_provider" || exit 1
        apply_provider "$new_provider"
        ;;
    apply)
        apply_provider "$(get_provider)"
        ;;
    *)
        echo "Usage: $(basename "$0") get|set <provider>|apply" >&2
        exit 1
        ;;
esac
