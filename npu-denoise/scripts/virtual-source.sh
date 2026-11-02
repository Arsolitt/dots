#!/usr/bin/env bash
# Virtual microphone that carries the denoised stream.
#
# start  spawn pw-loopback exposing npu_denoise (sink) and npu_mic (source)
# stop   terminate that loopback
# status report whether the pair exists
#
# A PulseAudio null-sink plus remap-source would do the same, but pipewire-pulse
# splits module arguments on whitespace, so device descriptions with spaces get
# truncated; pw-loopback takes SPA JSON and keeps them intact.
set -euo pipefail

sink_name=npu_denoise
source_name=npu_mic
sink_description="NPU denoise sink"
source_description="Microphone (NPU denoised)"
state_file=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/npu-denoise.pid

sink_present() {
    pactl list short sinks | awk '{print $2}' | grep -qx "$sink_name"
}

source_present() {
    pactl list short sources | awk '{print $2}' | grep -qx "$source_name"
}

loopback_pid() {
    [[ -r $state_file ]] || return 0
    local pid
    pid=$(<"$state_file")
    if [[ -n $pid ]] && kill -0 "$pid" 2>/dev/null; then
        echo "$pid"
    fi
}

cmd_start() {
    if sink_present && source_present; then
        echo "already running: $sink_name / $source_name"
        return 0
    fi
    local stale
    stale=$(loopback_pid || true)
    if [[ -n ${stale:-} ]]; then
        kill "$stale" 2>/dev/null || true
        sleep 0.3
    fi

    pw-loopback \
        --capture-props="{\"media.class\":\"Audio/Sink\",\"node.name\":\"$sink_name\",\"node.description\":\"$sink_description\"}" \
        --playback-props="{\"media.class\":\"Audio/Source\",\"node.name\":\"$source_name\",\"node.description\":\"$source_description\"}" \
        >/dev/null 2>&1 &
    local pid=$!
    echo "$pid" >"$state_file"

    local attempt
    for attempt in $(seq 1 40); do
        if sink_present && source_present; then
            echo "started $sink_name / $source_name (pid $pid)"
            return 0
        fi
        sleep 0.1
    done
    echo "failed to expose $sink_name / $source_name" >&2
    return 1
}

cmd_stop() {
    local pid
    pid=$(loopback_pid || true)
    if [[ -n ${pid:-} ]]; then
        kill "$pid" 2>/dev/null || true
    fi
    rm -f "$state_file"
    local attempt
    for attempt in $(seq 1 30); do
        if ! sink_present && ! source_present; then
            echo "stopped"
            return 0
        fi
        sleep 0.1
    done
    echo "still present: $sink_name / $source_name" >&2
    return 1
}

cmd_status() {
    local pid
    pid=$(loopback_pid || true)
    if sink_present; then echo "sink   $sink_name: present"; else echo "sink   $sink_name: missing"; fi
    if source_present; then echo "source $source_name: present"; else echo "source $source_name: missing"; fi
    if [[ -n ${pid:-} ]]; then echo "loopback: pid $pid"; else echo "loopback: not running"; fi
}

case "${1:-status}" in
    start) cmd_start ;;
    stop) cmd_stop ;;
    status) cmd_status ;;
    *)
        echo "usage: $(basename "$0") start|stop|status" >&2
        exit 2
        ;;
esac
