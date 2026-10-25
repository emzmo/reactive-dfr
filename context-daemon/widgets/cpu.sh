#!/bin/sh
# Touch Bar widget: CPU usage percentage
# Output: JSON {"text":"42%","color":"#...","icon":"memory"}
# Color shifts: green < 60%, yellow < 85%, red >= 85%

idle=$(head -1 /proc/stat | awk '{print $5}')
total=$(head -1 /proc/stat | awk '{s=0; for(i=2;i<=NF;i++) s+=$i; print s}')

if [ -z "$idle" ] || [ -z "$total" ] || [ "$total" -eq 0 ]; then
    printf '{"text":"n/a","icon":"memory"}'
    exit 1
fi

usage=$((100 - (idle * 100 / total)))

if [ "$usage" -ge 85 ]; then
    color="#cc3333"
elif [ "$usage" -ge 60 ]; then
    color="#ccaa33"
else
    color="#33cc44"
fi

printf '{"text":"%d%%","color":"%s","icon":"memory"}' "$usage" "$color"