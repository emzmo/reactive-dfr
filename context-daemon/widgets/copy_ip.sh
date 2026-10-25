#!/bin/sh
# Touch Bar widget OnClick: copy IP to Wayland clipboard
# wl-copy needs WAYLAND_DISPLAY and XDG_RUNTIME_DIR which may not be
# inherited by the daemon's spawned shell process.

export XDG_RUNTIME_DIR="/run/user/$(id -u)"
export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}"

ip=$(ip -4 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)

if [ -z "$ip" ]; then
    exit 1
fi

echo -n "$ip" | wl-copy