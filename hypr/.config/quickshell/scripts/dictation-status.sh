#!/bin/bash
# Quickshell: OpenWhispr dictation status in the bar.
# States: recording (MIC/REC), transcribing (MIC/TX), app down (MIC/OFF), idle (hidden).

readonly LOG="${OPENWHISPR_LOG:-/tmp/openwhispr.log}"
readonly TX_STAMP="/tmp/openwhispr-tx.stamp"
readonly TX_GRACE_SEC=15

emit() {
    printf '%s\n' "$1"
}

dbus_up() {
    dbus-send --session --print-reply --dest=org.freedesktop.DBus \
        /org/freedesktop/DBus org.freedesktop.DBus.NameHasOwner \
        string:com.openwhispr.App 2>/dev/null \
        | rg -q 'boolean true'
}

app_up() {
    pgrep -f '/opt/openwhispr/open-whispr( |$)' >/dev/null 2>&1 \
        || pgrep -x open-whispr-app >/dev/null 2>&1
}

# Pulse/PipeWire capture stream from OpenWhispr / Electron
recording_pulse() {
    if pactl list source-outputs 2>/dev/null \
        | rg -q 'application\.process\.binary = "open-whispr(-app)?"|application\.name = "[^"]*[Oo]pen[Ww]hispr|application\.name = "Chromium input"'; then
        if pactl list source-outputs 2>/dev/null \
            | rg -q 'application\.process\.binary = "open-whispr(-app)?"|application\.name = "[^"]*[Oo]pen[Ww]hispr'; then
            return 0
        fi
        local pids
        pids=$(pgrep -d'|' -f '/opt/openwhispr/open-whispr( |$)|open-whispr-app' 2>/dev/null) || true
        [[ -z "${pids:-}" ]] && return 1
        pactl list source-outputs 2>/dev/null \
            | rg -q "application\\.process\\.id = \"(${pids})\""
        return $?
    fi
    return 1
}

# Log phase from OpenWhispr stdout (when launched with log redirect)
log_phase() {
    [[ -f "$LOG" ]] || { echo idle; return; }
    local line
    line=$(rg -N 'Recording started with microphone|Recording stopped|Transcription mode:|Pipeline failed|Pipeline complete|transcription completed' "$LOG" 2>/dev/null | tail -1) || true
    case "$line" in
        *"Recording started"*) echo rec ;;
        *"Recording stopped"*|*"Transcription mode:"*) echo tx ;;
        *"Pipeline failed"*|*"Pipeline complete"*|*"transcription completed"*) echo idle ;;
        *) echo idle ;;
    esac
}

legacy_recording() {
    local pid_file="/tmp/stt-dictate.pid" pid
    [[ -f "$pid_file" ]] || return 1
    pid=$(cat "$pid_file" 2>/dev/null) || return 1
    [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null
}

tx_grace_active() {
    [[ -f "$TX_STAMP" ]] || return 1
    local now stamp
    now=$(date +%s)
    stamp=$(cat "$TX_STAMP" 2>/dev/null) || return 1
    [[ -n "$stamp" ]] || return 1
    (( now - stamp < TX_GRACE_SEC ))
}

alive=0
dbus_up && alive=1
app_up && alive=1

if (( alive )); then
    phase=$(log_phase)

    if [[ "$phase" == "rec" ]] || recording_pulse || legacy_recording; then
        date +%s > "$TX_STAMP"
        emit '{"text":"MIC\\nREC","tooltip":"OpenWhispr recording — Ctrl+Super to stop","class":"high"}'
        exit 0
    fi

    # Pipeline done/failed → idle; drop grace so bar does not stick on TX
    if [[ "$phase" == "idle" ]]; then
        rm -f "$TX_STAMP"
        emit '{"text":"","tooltip":"","class":"hidden"}'
        exit 0
    fi

    if [[ "$phase" == "tx" ]] || tx_grace_active; then
        if [[ "$phase" == "tx" ]]; then
            date +%s > "$TX_STAMP"
        fi
        emit '{"text":"MIC\\nTX","tooltip":"OpenWhispr transcribing…","class":"active"}'
        exit 0
    fi

    rm -f "$TX_STAMP"
    emit '{"text":"","tooltip":"","class":"hidden"}'
    exit 0
fi

# App dead — ignore stale log / grace so bar does not stick on REC
rm -f "$TX_STAMP"
emit '{"text":"MIC\\nOFF","tooltip":"OpenWhispr not running — hotkey will not work","class":"high"}'
