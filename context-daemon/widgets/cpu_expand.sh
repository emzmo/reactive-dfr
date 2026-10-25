#!/bin/sh
# Touch Bar expand widget: detailed CPU info
# Shown when the CPU widget is tapped (OnClick = "Expand")

load=$(cut -d' ' -f1-3 /proc/loadavg)
temp=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -1)
temp_c=$((temp / 1000))

top_proc=$(ps -eo comm,%cpu --sort=-%cpu --no-headers 2>/dev/null | head -1)
top_name=$(echo "$top_proc" | awk '{print $1}')
top_cpu=$(echo "$top_proc" | awk '{printf "%.0f", $2}')

printf '{"text":"load %s  %dC  %s(%d%%)","color":"#ccaa33"}' "$load" "$temp_c" "$top_name" "$top_cpu"