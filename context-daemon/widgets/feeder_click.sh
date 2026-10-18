#!/bin/sh
# feeder_click.sh — executes the feeder's OnClick action from the
# daemon's sandboxed context. The daemon can't use systemd-run --user
# (NoNewPrivileges=true blocks the user bus) or xdg-open directly
# (can't detect the DE). This script sets the session env vars
# manually and runs the action detached via setsid.

export HOME="$HOME"
if [ -z "$XDG_RUNTIME_DIR" ]; then
    XDG_RUNTIME_DIR="/run/user/$(id -u)"
    export XDG_RUNTIME_DIR
fi
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"

# Auto-detect Wayland display
if [ -z "$WAYLAND_DISPLAY" ]; then
    for wl in wayland-1 wayland-0; do
        if [ -S "$XDG_RUNTIME_DIR/$wl" ]; then
            export WAYLAND_DISPLAY="$wl"
            break
        fi
    done
fi

ACTION=$(cat "${CACHE_DIRECTORY:-/var/cache/reactive-dfr}/feeder_action.txt" 2>/dev/null)
if [ -n "$ACTION" ]; then
    setsid sh -c "$ACTION" >/dev/null 2>&1 &
fi