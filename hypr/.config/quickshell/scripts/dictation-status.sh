#!/bin/bash
# Waybar: show indicator while live dictation is active (no focus steal).

readonly PID_FILE="/tmp/stt-dictate.pid"

emit() {
    printf '%s\n' "$1"
}

if [[ -f "$PID_FILE" ]]; then
    pid=$(cat "$PID_FILE" 2>/dev/null) || true
    if [[ -n "${pid:-}" ]] && kill -0 "$pid" 2>/dev/null; then
        emit '{"text":"MIC","tooltip":"Dictating - ESC or Super+V to stop","class":"active"}'
        exit 0
    fi
fi

emit '{"text":"","tooltip":"","class":"idle"}'
