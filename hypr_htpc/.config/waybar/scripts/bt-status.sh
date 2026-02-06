#!/bin/bash
RELACON_MAC="FA:89:16:CF:37:2C"

# Check Relacon connection
relacon_connected=false
if bluetoothctl info $RELACON_MAC 2>/dev/null | grep -q "Connected: yes"; then
    relacon_connected=true
fi

# Check NuPhy keyboard (USB)
nuphy_connected=false
if grep -q "NuPhy Air60" /proc/bus/input/devices 2>/dev/null; then
    nuphy_connected=true
fi

# Build output with clear indicators
output=""
tooltip=""

if [ "$relacon_connected" = true ]; then
    output="Mouse ✓"
    tooltip="Relacon: Connected"
else
    output="Mouse ✗"
    tooltip="Relacon: Disconnected"
fi

if [ "$nuphy_connected" = true ]; then
    output="${output}  KB ✓"
    tooltip="${tooltip} | Keyboard: Connected"
else
    output="${output}  KB ✗"
    tooltip="${tooltip} | Keyboard: Disconnected"
fi

# Add CSS class for styling disconnected state
class=""
if [ "$relacon_connected" = false ] || [ "$nuphy_connected" = false ]; then
    class="disconnected"
fi

echo "{\"text\": \"$output\", \"tooltip\": \"$tooltip\", \"class\": \"$class\"}"
