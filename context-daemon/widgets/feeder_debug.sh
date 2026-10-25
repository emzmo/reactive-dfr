#!/bin/sh
exec python3 "$HOME/.config/reactive-dfr/widgets/feeder.py" "$@" 2>>/tmp/feeder_stderr.log
