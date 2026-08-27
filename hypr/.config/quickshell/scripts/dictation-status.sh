#!/bin/bash
# Quickshell dictation overlay — Handy (Super+V via Hypr, not in-app shortcuts).
# States: recording (MIC/REC), transcribing (MIC/TX), app down (MIC/OFF), idle (hidden).

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

readonly LOG="${HANDY_LOG:-${XDG_DATA_HOME:-$HOME/.local/share}/com.pais.handy/logs/handy.log}"
readonly TX_STAMP="/tmp/handy-tx.stamp"
readonly CANCEL_FLAG="${XDG_RUNTIME_DIR:-/tmp}/handy-cancel.flag"
readonly TX_GRACE_SEC=8
readonly TX_MAX_SEC=45
readonly CANCEL_HOLD_SEC=3

emit() {
    printf '%s\n' "$1"
}

app_up() {
    pgrep -x handy >/dev/null 2>&1
}

handy_pids() {
    pgrep -x handy 2>/dev/null || true
}

# Handy captures via PipeWire's ALSA bridge — no application.process.binary on the stream.
recording_pulse() {
    if pactl list source-outputs 2>/dev/null \
        | rg -q 'PipeWire ALSA \[handy\]|application\.name = "PipeWire ALSA \[handy\]"'; then
        return 0
    fi
    if pactl list source-outputs 2>/dev/null \
        | rg -q 'application\.process\.binary = "handy"'; then
        return 0
    fi
    local pids
    pids=$(handy_pids)
    [[ -n "${pids:-}" ]] || return 1
    pactl list source-outputs 2>/dev/null \
        | rg -q "application\\.process\\.id = \"(${pids})\""
}

log_events() {
    [[ -f "$LOG" ]] || return 1
    local start
    start=$(rg -n 'Seeded [0-9]+ catalog model' "$LOG" 2>/dev/null | tail -1 | cut -d: -f1) || return 1
    [[ -n "$start" ]] || return 1
    tail -n +"$start" "$LOG"
}

# Phase from Handy debug log (current session only).
log_phase() {
    local line
    line=$(log_events 2>/dev/null \
        | rg -N 'TranscribeAction::start called|TranscribeAction::stop called|Starting async transcription task|Transcription completed|Transcription failed|Operation cancellation completed|Recording produced no audio' \
        2>/dev/null | tail -1) || true
    case "$line" in
        *"TranscribeAction::start called"*) echo rec ;;
        *"TranscribeAction::stop called"*|*"Starting async transcription"*) echo tx ;;
        *"Transcription completed"*|*"Transcription failed"*|*"Operation cancellation"*|*"Recording produced no audio"*) echo idle ;;
        *) echo idle ;;
    esac
}

stamp_age() {
    local file="${1:-$TX_STAMP}"
    [[ -f "$file" ]] || { echo 999999; return; }
    local now stamp
    now=$(date +%s)
    stamp=$(cat "$file" 2>/dev/null) || { echo 999999; return; }
    [[ -n "$stamp" ]] || { echo 999999; return; }
    echo $((now - stamp))
}

tx_grace_active() {
    local age
    age=$(stamp_age "$TX_STAMP")
    (( age < TX_GRACE_SEC ))
}

if [[ -f "$CANCEL_FLAG" ]]; then
    cage=$(stamp_age "$CANCEL_FLAG")
    if (( cage < CANCEL_HOLD_SEC )); then
        emit '{"text":"","tooltip":"","class":"hidden"}'
        exit 0
    fi
    rm -f "$CANCEL_FLAG"
fi

if app_up; then
    phase=$(log_phase)

    if recording_pulse || [[ "$phase" == "rec" ]]; then
        date +%s >"$TX_STAMP"
        emit '{"text":"MIC\\nREC","tooltip":"Super+V stop · Esc cancel","class":"high"}'
        exit 0
    fi

    if [[ "$phase" == "idle" ]]; then
        rm -f "$TX_STAMP"
        emit '{"text":"","tooltip":"","class":"hidden"}'
        exit 0
    fi

    if [[ "$phase" == "tx" ]] || tx_grace_active; then
        [[ "$phase" == "tx" ]] && date +%s >"$TX_STAMP"
        emit '{"text":"MIC\\nTX","tooltip":"Transcribing… Esc cancels","class":"active"}'
        exit 0
    fi

    if [[ -f "$TX_STAMP" ]]; then
        age=$(stamp_age "$TX_STAMP")
        if (( age < TX_MAX_SEC )); then
            emit '{"text":"MIC\\nTX","tooltip":"Transcribing… Esc cancels","class":"active"}'
            exit 0
        fi
        rm -f "$TX_STAMP"
    fi

    emit '{"text":"","tooltip":"","class":"hidden"}'
    exit 0
fi

rm -f "$TX_STAMP"
emit '{"text":"MIC\\nOFF","tooltip":"Handy not running — hotkey will start it","class":"high"}'
