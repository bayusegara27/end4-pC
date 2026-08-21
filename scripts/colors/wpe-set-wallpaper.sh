#!/usr/bin/env bash

# Put a Wallpaper Engine wallpaper on the focused screen.
#
# The assignment cannot simply be written while wpe-manager runs: its rotation
# controller loads state.json once, at construction, and never re-reads it. The
# next action in its GUI would then save that stale copy back and silently
# revert the choice. So the manager is stopped first, the assignment written,
# and the manager started again — it re-reads state.json and applies it through
# its own restore path, which also keeps its in-memory state correct.
#
# The running backend is deliberately left alive across that gap so the incoming
# manager performs its usual overlapping swap rather than the screen going black.
#
# Usage: wpe-set-wallpaper.sh <workshop-id>

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WPE_CONFIG_FILE="$XDG_CONFIG_HOME/wpe-manager/config.json"
WPE_STATE_FILE="$XDG_CONFIG_HOME/wpe-manager/state.json"
PROVIDER_SCRIPT="$SCRIPT_DIR/wallpaper-provider.sh"

wallpaper_id="${1:-}"
if [[ ! "$wallpaper_id" =~ ^[0-9]+$ ]]; then
    echo "Usage: $(basename "$0") <workshop-id>" >&2
    exit 1
fi

library_dir=""
if [[ -f "$WPE_CONFIG_FILE" ]]; then
    library_dir="$(jq -r '.library_dir // empty' "$WPE_CONFIG_FILE" 2>/dev/null)"
fi
if [[ -z "$library_dir" || ! -d "$library_dir/$wallpaper_id" ]]; then
    echo "Wallpaper $wallpaper_id is not in the library" >&2
    exit 1
fi

screen="$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused) | .name' 2>/dev/null)"
if [[ -z "$screen" ]]; then
    screen="$(hyprctl monitors -j 2>/dev/null | jq -r '.[0].name // empty' 2>/dev/null)"
fi
if [[ -z "$screen" ]]; then
    echo "Could not determine which screen to assign" >&2
    exit 1
fi

# Choosing a live wallpaper means wanting the live wallpaper provider.
if [[ "$("$PROVIDER_SCRIPT" get)" != "wallpaperengine" ]]; then
    "$PROVIDER_SCRIPT" set wallpaperengine
else
    "$PROVIDER_SCRIPT" stop-manager
fi

mkdir -p "$(dirname "$WPE_STATE_FILE")"
[[ -f "$WPE_STATE_FILE" ]] || echo '{"assignments":{}}' > "$WPE_STATE_FILE"

# Drop every assignment covering this screen first — a key may be a comma-joined
# span ("DP-1,HDMI-A-1") — then assign it on its own, mirroring what
# rotation.assign_single does.
if jq --arg screen "$screen" --arg id "$wallpaper_id" '
        (.assignments // {}) as $existing
        | .assignments = (
            $existing
            | with_entries(select((.key | split(",")) | index($screen) | not))
          )
        | .assignments[$screen] = { mode: "single", id: $id }
    ' "$WPE_STATE_FILE" > "$WPE_STATE_FILE.tmp" 2>/dev/null; then
    mv "$WPE_STATE_FILE.tmp" "$WPE_STATE_FILE"
else
    rm -f "$WPE_STATE_FILE.tmp"
    echo "Failed to write the assignment" >&2
    "$PROVIDER_SCRIPT" start-manager
    exit 1
fi

"$PROVIDER_SCRIPT" start-manager
