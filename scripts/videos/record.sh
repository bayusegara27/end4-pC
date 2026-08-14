#!/usr/bin/env bash
CONFIG_FILE="$HOME/.config/illogical-impulse/config.json"
JSON_PATH=".screenRecord.savePath"
CUSTOM_PATH=$(jq -r "$JSON_PATH" "$CONFIG_FILE" 2>/dev/null)
RECORDING_DIR=""
if [[ -n "$CUSTOM_PATH" && "$CUSTOM_PATH" != "null" ]]; then
    RECORDING_DIR="$CUSTOM_PATH"
else
    RECORDING_DIR="$HOME/Videos"
fi

set_recording_state() {
    local state=$1
    local STATE_FILE="$HOME/.local/state/quickshell/states.json"
    if [[ -f "$STATE_FILE" ]]; then
        local tmp=$(mktemp)
        if jq ".record.enable = $state" "$STATE_FILE" > "$tmp" 2>/dev/null; then
            cat "$tmp" > "$STATE_FILE"
            rm -f "$tmp"
        fi
    fi
}

getdate() {
    date '+%Y-%m-%d_%H.%M.%S'
}

getaudiooutput() {
    pactl list sources 2>/dev/null | grep 'Name' | grep 'monitor' | head -n 1 | cut -d ' ' -f2
}

detect_compositor() {
    local combined
    combined="$(echo "${XDG_CURRENT_DESKTOP:-} ${XDG_SESSION_DESKTOP:-}" | tr '[:upper:]' '[:lower:]')"
    if [[ "$combined" == *"niri"* ]]; then
        echo "niri"
    elif [[ "$combined" == *"hyprland"* ]]; then
        echo "hyprland"
    else
        echo "unknown"
    fi
}

getactivemonitor() {
    if [[ "$(detect_compositor)" == "niri" ]]; then
        niri msg -j workspaces | jq -r '.[] | select(.is_focused == true) | .output'
    else
        hyprctl monitors -j | jq -r '.[] | select(.focused == true) | .name'
    fi
}

mkdir -p "$RECORDING_DIR"
cd "$RECORDING_DIR" || exit

ARGS=("$@")
MANUAL_REGION=""
SOUND_FLAG=0
SOUND_MIC_FLAG=0
FULLSCREEN_FLAG=0
for ((i=0;i<${#ARGS[@]};i++)); do
    if [[ "${ARGS[i]}" == "--region" ]]; then
        if (( i+1 < ${#ARGS[@]} )); then
            MANUAL_REGION="${ARGS[i+1]}"
        else
            notify-send "Recording cancelled" "No region specified for --region" -a 'Recorder' & disown
            exit 1
        fi
    elif [[ "${ARGS[i]}" == "--sound" ]]; then
        SOUND_FLAG=1
    elif [[ "${ARGS[i]}" == "--sound-mic" ]]; then
        SOUND_MIC_FLAG=1
    elif [[ "${ARGS[i]}" == "--fullscreen" ]]; then
        FULLSCREEN_FLAG=1
    fi
done

# Stop existing recording if already running
if pgrep -f "gpu-screen-recorder" > /dev/null; then
    notify-send "Recording Stopped" "Video saved to $RECORDING_DIR" -a 'Recorder' &
    pkill -SIGINT -f "gpu-screen-recorder" 2>/dev/null || true
    set_recording_state false
    exit 0
fi

OUT_FILE="${RECORDING_DIR}/recording_$(getdate).mp4"

if command -v gpu-screen-recorder &>/dev/null; then
    notify-send "Starting recording (GPU NVENC)" "$(basename "$OUT_FILE")" -a 'Recorder' & disown
    set_recording_state true
    AUDIO_ARGS=()
    if [[ $SOUND_FLAG -eq 1 ]]; then
        AUDIO_ARGS=(-a "default_output")
        if [[ $SOUND_MIC_FLAG -eq 1 ]]; then
            AUDIO_ARGS+=(-a "default_input")
        fi
    fi

    if [[ $FULLSCREEN_FLAG -eq 1 ]]; then
        gpu-screen-recorder -w screen -f 60 "${AUDIO_ARGS[@]}" -o "$OUT_FILE"
    else
        if [[ -z "$MANUAL_REGION" ]]; then
            if ! region="$(slurp -f "%wx%h+%x+%y" 2>&1)"; then
                notify-send "Recording cancelled" "Selection was cancelled" -a 'Recorder' & disown
                set_recording_state false
                exit 1
            fi
        else
            region="$MANUAL_REGION"
        fi
        gpu-screen-recorder -w "$region" -f 60 "${AUDIO_ARGS[@]}" -o "$OUT_FILE"
    fi
    set_recording_state false
else
    notify-send "Recording Error" "gpu-screen-recorder is not installed." -a 'Recorder' & disown
fi