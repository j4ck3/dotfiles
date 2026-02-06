#!/bin/bash
# Auto-reconnect Relacon Bluetooth mouse

RELACON_MAC="FA:89:16:CF:37:2C"

# Check if already connected
if timeout 2s bluetoothctl info $RELACON_MAC 2>/dev/null | grep -q "Connected: yes"; then
    exit 0
fi

# Quick connect attempt with timeout (device must be awake/advertising)
timeout 5s bluetoothctl connect $RELACON_MAC &>/dev/null
