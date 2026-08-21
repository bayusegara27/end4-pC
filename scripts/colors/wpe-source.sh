#!/usr/bin/env bash

# Resolve the wallpaper linux-wallpaperengine is currently showing to a still
# image that colorgen can read.
#
# Wallpaper Engine scenes are `scene.pkg` bundles rather than images or videos,
# so the only still that represents one is the Workshop preview named in its
# project.json. Most of those previews are animated GIFs, so the first frame is
# extracted and cached as a JPEG.
#
# Prints the cached still's path (or, with --id, the wallpaper id) and exits 0.
# Exits 1 without output when no live wallpaper can be resolved.

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

WPE_CONFIG_FILE="$XDG_CONFIG_HOME/wpe-manager/config.json"
WPE_ENGINE_FILE="$XDG_CONFIG_HOME/wpe-manager/engine.json"
SHELL_CONFIG_FILE="$XDG_CONFIG_HOME/illogical-impulse/config.json"
STILL_DIR="$XDG_STATE_HOME/quickshell/user/generated/wallpaper/wpe"

print_id_only=""
[[ "${1:-}" == "--id" ]] && print_id_only="1"

# The wallpaper provider setting decides who owns the background. When the
# shell owns it, a stray backend left running must not hijack colorgen. An
# unset value means "no choice made yet" and keeps the old behaviour of simply
# detecting whatever is running.
if [[ -f "$SHELL_CONFIG_FILE" ]]; then
    provider="$(jq -r '.background.provider // ""' "$SHELL_CONFIG_FILE" 2>/dev/null)"
    [[ "$provider" == "shell" ]] && exit 1
fi

pid_alive() {
    [[ "$1" =~ ^[0-9]+$ ]] && kill -0 "$1" 2>/dev/null
}

library_dir=""
if [[ -f "$WPE_CONFIG_FILE" ]]; then
    library_dir="$(jq -r '.library_dir // empty' "$WPE_CONFIG_FILE" 2>/dev/null)"
fi

# wpe-manager's engine.json is the authoritative "what is on each screen right
# now" map: it is rewritten on every switch and every playlist rotation. Only
# entries whose backend process is still alive count, so a file left over from
# a previous session is ignored.
wallpaper_ref=""
focused_monitor="$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.focused) | .name' 2>/dev/null)"

if [[ -f "$WPE_ENGINE_FILE" ]]; then
    while IFS=$'\t' read -r screens pid id; do
        [[ -z "$id" || "$id" == "null" ]] && continue
        pid_alive "$pid" || continue
        # First alive entry wins unless a later one owns the focused monitor.
        # An assignment key may span several screens ("HDMI-A-1,DP-1").
        [[ -z "$wallpaper_ref" ]] && wallpaper_ref="$id"
        if [[ -n "$focused_monitor" ]]; then
            case ",$screens," in
                *",$focused_monitor,"*) wallpaper_ref="$id"; break ;;
            esac
        fi
    done < <(jq -r 'to_entries[] | [.key, (.value.pid | tostring), (.value.id // "")] | @tsv' \
                "$WPE_ENGINE_FILE" 2>/dev/null)
fi

# Fallback: a backend started outside wpe-manager (e.g. a hyprland exec-once)
# never appears in engine.json, so read the --bg argument off the running
# process instead. The highest pid is the most recently started one.
if [[ -z "$wallpaper_ref" ]]; then
    while read -r _pid args; do
        bg="$(sed -n 's/.*--bg[ =]\+\([^ ]\+\).*/\1/p' <<< "$args")"
        [[ -n "$bg" ]] && wallpaper_ref="$bg"
    done < <(pgrep -a linux-wallpaperengine 2>/dev/null)
fi

[[ -n "$wallpaper_ref" ]] || exit 1

# --bg takes either a full path into the Workshop library or a bare id.
if [[ -d "$wallpaper_ref" ]]; then
    wallpaper_dir="${wallpaper_ref%/}"
elif [[ -n "$library_dir" && -d "$library_dir/$wallpaper_ref" ]]; then
    wallpaper_dir="$library_dir/$wallpaper_ref"
else
    exit 1
fi
wallpaper_id="$(basename "$wallpaper_dir")"

if [[ -n "$print_id_only" ]]; then
    echo "$wallpaper_id"
    exit 0
fi

preview_name="preview.jpg"
if [[ -f "$wallpaper_dir/project.json" ]]; then
    declared="$(jq -r '.preview // empty' "$wallpaper_dir/project.json" 2>/dev/null)"
    [[ -n "$declared" ]] && preview_name="$declared"
fi

preview="$wallpaper_dir/$preview_name"
if [[ ! -f "$preview" ]]; then
    preview="$(find "$wallpaper_dir" -maxdepth 1 -iname 'preview.*' -print -quit 2>/dev/null)"
fi
[[ -n "$preview" && -f "$preview" ]] || exit 1

still="$STILL_DIR/$wallpaper_id.jpg"
if [[ ! -s "$still" || "$preview" -nt "$still" ]]; then
    mkdir -p "$STILL_DIR"
    # `[0]` takes the first frame — animated GIF previews are the norm in the
    # Workshop and matugen needs a single opaque frame.
    if ! magick "${preview}[0]" -coalesce -background black -alpha remove -alpha off \
            -quality 92 "$still" 2>/dev/null; then
        rm -f "$still"
        exit 1
    fi
    [[ -s "$still" ]] || { rm -f "$still"; exit 1; }
fi

echo "$still"
