#!/bin/sh
# Touch Bar expand widget: detailed network info
# Shown when the IP widget is tapped (OnClick = "Expand")

ip_addr=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)

if [ -z "$ip_addr" ]; then
    printf '{"text":"offline","color":"#cc3333"}'
    exit 1
fi

gateway=$(ip route show default 2>/dev/null | awk '{print $3}' | head -1)
ssid=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | grep '^yes:' | cut -d: -f2)
[ -z "$ssid" ] && ssid="wired"

if [ "$ssid" = "wired" ]; then
    printf '{"text":"%s  gw:%s","color":"#33cc44"}' "$ip_addr" "$gateway"
else
    printf '{"text":"%s  %s  gw:%s","color":"#33cc44"}' "$ip_addr" "$ssid" "$gateway"
fi