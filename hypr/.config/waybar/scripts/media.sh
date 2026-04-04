#!/bin/bash
# Waybar custom module: Spotify only via playerctl.
# Uses playerctl --follow for instant updates.
# Exit cleanly when Waybar closes the pipe (reload/quit) to avoid "Broken pipe" spam.
trap 'exit 0' PIPE

PLAYER_ARG="--player=spotify"

emit_json() {
    /usr/bin/printf '%s\n' "$1" || exit 0
}

output() {
    STATUS=$(playerctl $PLAYER_ARG status 2>/dev/null)
    exit=$?
    if [ $exit -ne 0 ] || [ -z "$STATUS" ]; then
        emit_json '{"text":"","tooltip":"","class":"stopped"}'
        return
    fi

    if [ "$STATUS" = "Playing" ] || [ "$STATUS" = "Paused" ]; then
        ARTIST=$(playerctl $PLAYER_ARG metadata --format '{{ artist }}' 2>/dev/null)
        TITLE=$(playerctl $PLAYER_ARG metadata --format '{{ title }}' 2>/dev/null)
        PLAYER=$(playerctl $PLAYER_ARG metadata --format '{{ playerName }}' 2>/dev/null)

        if [ "$STATUS" = "Playing" ]; then
            ICON="󰏤"
        else
            ICON="󰐊"
        fi

        TEXT="$ICON $ARTIST - $TITLE"
        TOOLTIP="$ARTIST - $TITLE
$PLAYER"

        # Escape for JSON
        TEXT_ESC=$(printf '%s' "$TEXT" | sed 's/\\/\\\\/g; s/"/\\"/g')
        TOOLTIP_ESC=$(printf '%s' "$TOOLTIP" | sed 's/\\/\\\\/g; s/"/\\"/g' | awk '{printf "%s%s", (NR>1?"\\n":""), $0}')

        emit_json "{\"text\": \"$TEXT_ESC\", \"tooltip\": \"$TOOLTIP_ESC\", \"class\": \"$STATUS\"}"
    else
        emit_json '{"text":"","tooltip":"","class":"stopped"}'
    fi
}

# Initial state
output

# Follow metadata/status changes (re-run output on any change)
playerctl $PLAYER_ARG --follow metadata --format '{{ artist }} {{ title }} {{ status }}' 2>/dev/null | while read -r _; do
    output
done
