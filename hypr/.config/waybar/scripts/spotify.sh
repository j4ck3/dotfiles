#!/bin/bash
# Waybar custom module for Spotify: song title, play/pause icon, volume
# Uses event-based monitoring for instant updates
trap 'exit 0' PIPE

output() {
    STATUS=$(playerctl --player=spotify status 2>/dev/null)

    if [ "$STATUS" = "Playing" ] || [ "$STATUS" = "Paused" ]; then
        ARTIST=$(playerctl --player=spotify metadata artist 2>/dev/null)
        TITLE=$(playerctl --player=spotify metadata title 2>/dev/null)

        ID=$(pactl list sink-inputs | grep -B20 'application.name = "spotify"' | grep 'Sink Input' | awk '{print $3}' | tr -d '#' | head -1)
        if [ -n "$ID" ]; then
            VOL=$(pactl list sink-inputs | grep -A20 "Sink Input #$ID" | grep 'Volume:' | head -1 | grep -o '[0-9]*%' | head -1)
        else
            VOL=""
        fi

        if [ "$STATUS" = "Playing" ]; then
            ICON="󰏤"
        else
            ICON="󰐊"
        fi

        TEXT="$ICON $ARTIST - $TITLE $VOL"
        TOOLTIP="$ARTIST - $TITLE ($VOL)"

        echo "{\"text\": \"$TEXT\", \"tooltip\": \"$TOOLTIP\", \"class\": \"$STATUS\"}"
    else
        echo "{\"text\": \"\", \"tooltip\": \"\", \"class\": \"stopped\"}"
    fi
}

# Print initial state
output

# Merge both event streams into one using process substitution
{
    playerctl --player=spotify --follow metadata --format 'metadata_change' 2>/dev/null &
    pactl subscribe 2>/dev/null | grep --line-buffered 'sink-input' &
    wait
} | while read -r _; do
    sleep 0.05
    # Drain queued events
    while read -r -t 0.05 _; do :; done
    output
done
