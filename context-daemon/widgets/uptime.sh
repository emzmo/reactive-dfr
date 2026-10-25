#!/bin/sh
# Touch Bar widget: system uptime
# Output: JSON {"text":"2d 3h","icon":"schedule"}

up_seconds=$(cut -d. -f1 /proc/uptime)

if [ "$up_seconds" -ge 86400 ]; then
    days=$((up_seconds / 86400))
    hours=$(( (up_seconds % 86400) / 3600 ))
    text="${days}d ${hours}h"
elif [ "$up_seconds" -ge 3600 ]; then
    hours=$((up_seconds / 3600))
    mins=$(( (up_seconds % 3600) / 60 ))
    text="${hours}h ${mins}m"
else
    mins=$((up_seconds / 60))
    text="${mins}m"
fi

printf '{"text":"%s","icon":"schedule"}' "$text"