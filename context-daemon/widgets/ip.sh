#!/bin/sh
# Touch Bar widget: local IP address
# Output: JSON {"text":"192.168.1.42","icon":"network_wifi"}

ip=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)

if [ -z "$ip" ]; then
    printf '{"text":"no net","color":"#cc3333","icon":"signal_wifi_off"}'
    exit 1
fi

printf '{"text":"%s","icon":"network_wifi"}' "$ip"