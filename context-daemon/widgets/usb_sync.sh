#!/bin/sh
# usb_sync.sh — Touch Bar widget that shows USB sync status
#
# Reads the state file written by recorder_sync.sh and outputs JSON
# for the reactive-dfr Command widget.  Shows colored status text
# while a sync is in progress, and nothing when idle.
#
# States:
#   syncing → orange "Sync"
#   done    → green  "Done"
#   error   → red    "Error"
#   (none)  → empty (widget shows nothing)

STATE_FILE="${HOME}/.config/reactive-dfr/state/usb_sync.state"

if [ ! -f "$STATE_FILE" ]; then
    exit 0
fi

state=$(cat "$STATE_FILE" 2>/dev/null)

case "$state" in
    syncing)
        printf '{"text":"Sync","color":"#cc8833","icon":"sync"}'
        ;;
    done)
        printf '{"text":"Done","color":"#33cc44","icon":"check_circle"}'
        ;;
    error)
        printf '{"text":"Error","color":"#cc3333","icon":"error"}'
        ;;
    *)
        exit 0
        ;;
esac