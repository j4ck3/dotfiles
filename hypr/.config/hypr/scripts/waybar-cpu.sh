#!/bin/bash

# Get CPU usage using top (simple and reliable)
CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{printf "%.0f", 100 - $1}')

# If CPU usage is over 3%, get the top process
if [ "$CPU_USAGE" -gt 3 ]; then
    # Get the process name with highest CPU usage (excluding kernel threads)
    TOP_PROCESS=$(ps aux --sort=-%cpu | awk 'NR==2 && $3 > 0.1 && $11 !~ /^\[/ {for(i=11;i<=NF;i++) printf "%s ", $i; print ""}' | head -c 20 | sed 's/[[:space:]]*$//')
    if [ -n "$TOP_PROCESS" ]; then
        echo "CPU: ${CPU_USAGE}% ${TOP_PROCESS}"
    else
        echo "CPU: ${CPU_USAGE}%"
    fi
else
    echo "CPU: ${CPU_USAGE}%"
fi

Ekalmen""22