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

default_sink_monitor() {
    local sink
    sink="$(pactl get-default-sink 2>/dev/null)"
    [[ -n "$sink" ]] && echo "${sink}.monitor"
}

default_microphone() {
    local source
    source="$(pactl get-default-source 2>/dev/null)"
    if [[ -n "$source" && "$source" != *.monitor ]]; then
        echo "$source"
    fi
}

MIX_MODULES=()
cleanup_audio() {
    for module in "${MIX_MODULES[@]}"; do
        pactl unload-module "$module" >/dev/null 2>&1
    done
    MIX_MODULES=()
}

AUDIO_SOURCE=""
build_audio_source() {
    local want_system=$1 want_mic=$2 system_source mic_source
    AUDIO_SOURCE=""
    system_source=""
    mic_source=""
    [[ $want_system -eq 1 ]] && system_source="$(default_sink_monitor)"
    if [[ $want_mic -eq 1 ]]; then
        mic_source="$(default_microphone)"
        if [[ -z "$mic_source" ]]; then
            notify-send "No microphone found" "Recording without microphone" -a 'Recorder' & disown
        fi
    fi

    if [[ -n "$system_source" && -n "$mic_source" ]]; then
        local mix="qs_record_mix" module
        module=$(pactl load-module module-null-sink sink_name="$mix" sink_properties=device.description=QuickshellRecordMix) || return
        MIX_MODULES+=("$module")
        module=$(pactl load-module module-loopback source="$system_source" sink="$mix" latency_msec=30) && MIX_MODULES+=("$module")
        module=$(pactl load-module module-loopback source="$mic_source" sink="$mix" latency_msec=30) && MIX_MODULES+=("$module")
        AUDIO_SOURCE="${mix}.monitor"
    elif [[ -n "$system_source" ]]; then
        AUDIO_SOURCE="$system_source"
    elif [[ -n "$mic_source" ]]; then
        AUDIO_SOURCE="$mic_source"
    fi
}

toggle_microphone() {
    local mic
    mic="$(default_microphone)"
    if [[ -z "$mic" ]]; then
        notify-send "No microphone found" "Nothing to mute" -a 'Recorder' & disown
        exit 1
    fi
    pactl set-source-mute "$mic" toggle
    if pactl get-source-mute "$mic" | grep -q yes; then
        notify-send "Microphone muted" -a 'Recorder' & disown
    else
        notify-send "Microphone on" -a 'Recorder' & disown
    fi
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
MIC_FLAG=0
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
    elif [[ "${ARGS[i]}" == "--sound-mic" || "${ARGS[i]}" == "--mic" ]]; then
        SOUND_MIC_FLAG=1
        MIC_FLAG=1
    elif [[ "${ARGS[i]}" == "--fullscreen" ]]; then
        FULLSCREEN_FLAG=1
    elif [[ "${ARGS[i]}" == "--toggle-mic" ]]; then
        toggle_microphone
        exit 0
    fi
done

# Stop existing recording if already running (SIGINT triggers finalization in main process)
if pgrep -f "gpu-screen-recorder" > /dev/null; then
    pkill -SIGINT -f "gpu-screen-recorder" 2>/dev/null || true
    exit 0
fi

if pgrep wf-recorder > /dev/null; then
    notify-send "Recording Stopped" "Stopped" -a 'Recorder' &
    pkill wf-recorder &
    set_recording_state false
    exit 0
fi

OUT_FILE="${RECORDING_DIR}/recording_$(getdate).mp4"

if command -v gpu-screen-recorder &>/dev/null; then
    # Silent start: zero toast popups to avoid polluting video frames
    set_recording_state true
    AUDIO_ARGS=()
    if [[ $SOUND_FLAG -eq 1 ]]; then
        AUDIO_ARGS=(-a "default_output")
    fi
    if [[ $SOUND_MIC_FLAG -eq 1 || $MIC_FLAG -eq 1 ]]; then
        AUDIO_ARGS+=(-a "default_input")
    fi

    GSR_LOG="$(mktemp -t gsr-record.XXXXXX.log)"

    if [[ $FULLSCREEN_FLAG -eq 1 ]]; then
        GSR_ARGS=(-w screen -f 60 "${AUDIO_ARGS[@]}" -o "$OUT_FILE")
    else
        if [[ -z "$MANUAL_REGION" ]]; then
            if ! region="$(slurp -f "%wx%h+%x+%y" 2>&1)"; then
                notify-send "Recording cancelled" "Selection was cancelled" -a 'Recorder' -i 'screen_record' & disown
                set_recording_state false
                rm -f "$GSR_LOG"
                exit 1
            fi
        else
            region="$MANUAL_REGION"
        fi
        GSR_ARGS=(-w "$region" -f 60 "${AUDIO_ARGS[@]}" -o "$OUT_FILE")
    fi

    gpu-screen-recorder "${GSR_ARGS[@]}" >"$GSR_LOG" 2>&1
    GSR_RC=$?
    set_recording_state false

    # Gagal start (mis. VRAM habis -> NVENC tidak bisa init CUDA)
    if command -v gsr-diagnose >/dev/null 2>&1; then
        gsr-diagnose "$GSR_LOG" "$GSR_RC" "Recorder" || { rm -f "$GSR_LOG"; exit 1; }
    elif [[ $GSR_RC -ne 0 ]]; then
        notify-send -u critical "Recording failed"             "$(grep -m1 -i 'gsr error' "$GSR_LOG" | cut -c1-160)" -a 'Recorder' -i 'screen_record' & disown
        rm -f "$GSR_LOG"
        exit 1
    fi
    rm -f "$GSR_LOG"

    if [[ -f "$OUT_FILE" ]]; then
        # Generate lightweight static video thumbnail for instant notification preview
        THUMB_DIR="/tmp/quickshell/media/thumbnails"
        mkdir -p "$THUMB_DIR"
        THUMB_FILE="${THUMB_DIR}/thumb_$(basename "$OUT_FILE" .mp4).png"
        
        if command -v ffmpegthumbnailer &>/dev/null; then
            ffmpegthumbnailer -i "$OUT_FILE" -o "$THUMB_FILE" -s 640 -q 8 2>/dev/null || true
        elif command -v ffmpeg &>/dev/null; then
            ffmpeg -y -ss 0.5 -i "$OUT_FILE" -vframes 1 -q:v 2 "$THUMB_FILE" 2>/dev/null || true
        fi

        if [[ -f "$THUMB_FILE" ]]; then
            notify-send "Recording Saved" "Video saved to $OUT_FILE" -a 'Recorder' -i "$THUMB_FILE" &
        else
            notify-send "Recording Saved" "Video saved to $OUT_FILE" -a 'Recorder' -i 'screen_record' &
        fi
    fi
else
    # Fallback to wf-recorder
    if [[ $FULLSCREEN_FLAG -eq 0 ]]; then
        if [[ -n "$MANUAL_REGION" ]]; then
            region="$MANUAL_REGION"
        else
            if ! region="$(slurp 2>&1)"; then
                notify-send "Recording cancelled" "Selection was cancelled" -a 'Recorder' & disown
                exit 1
            fi
        fi
    fi

    trap cleanup_audio EXIT
    build_audio_source "$SOUND_FLAG" "$MIC_FLAG"
    RECORDER_ARGS=(--pixel-format yuv420p -f "$OUT_FILE")
    if [[ $FULLSCREEN_FLAG -eq 1 ]]; then
        RECORDER_ARGS+=(-o "$(getactivemonitor)")
    else
        RECORDER_ARGS+=(--geometry "$region")
    fi
    if [[ -n "$AUDIO_SOURCE" ]]; then
        RECORDER_ARGS+=("--audio=$AUDIO_SOURCE")
    fi

    notify-send "Starting recording" "$(basename "$OUT_FILE")" -a 'Recorder' & disown
    set_recording_state true
    wf-recorder "${RECORDER_ARGS[@]}"
    set_recording_state false

    if [[ -f "$OUT_FILE" ]]; then
        notify-send "Recording Saved" "Video saved to $OUT_FILE" -a 'Recorder' -i 'screen_record' &
    fi
fi
