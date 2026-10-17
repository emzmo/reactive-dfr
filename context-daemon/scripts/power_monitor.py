#!/usr/bin/env python3
"""power_monitor.py — toggle Touch Bar screensaver based on power state.

Monitors AC/battery and power profile every 10 seconds and creates or
removes the screensaver enable file accordingly:

  AC + performance  → enabled
  AC + balanced     → enabled
  AC + power-saver  → disabled
  Battery + performance → enabled
  Battery + balanced    → disabled
  Battery + power-saver → disabled

The enable file is: ~/.config/reactive-dfr/state/screensaver_enabled
The reactive-dfr daemon checks this file when the screensaver timeout
expires. See the daemon's ScreensaverMode for details.
"""

import os
import subprocess
import time
from pathlib import Path

STATE_FILE = Path.home() / ".config" / "reactive-dfr" / "state" / "screensaver_enabled"

# /sys/class/power_supply/ADP1/online: 1 = on AC, 0 = on battery
AC_PATH = "/sys/class/power_supply/ADP1/online"

POLL_INTERVAL = 10  # seconds


def is_on_ac():
    """Return True if the laptop is plugged in to AC power."""
    try:
        with open(AC_PATH) as f:
            return f.read().strip() == "1"
    except (OSError, FileNotFoundError):
        # Fallback: check battery status
        try:
            with open("/sys/class/power_supply/BAT0/status") as f:
                status = f.read().strip()
                return status in ("Charging", "Full", "Not charging")
        except OSError:
            return True  # assume AC if we can't tell


def get_power_profile():
    """Return the active power profile: 'performance', 'balanced', or 'power-saver'."""
    try:
        result = subprocess.run(
            ["powerprofilesctl", "get"],
            capture_output=True, text=True, timeout=3,
        )
        return result.stdout.strip()
    except (subprocess.SubprocessError, FileNotFoundError):
        return "balanced"  # safe default


def should_enable_screensaver(on_ac, profile):
    """Apply the behavior matrix and return True if screensaver should be enabled."""
    if on_ac:
        return profile != "power-saver"
    else:
        return profile == "performance"


def main():
    last_state = None
    while True:
        on_ac = is_on_ac()
        profile = get_power_profile()
        enable = should_enable_screensaver(on_ac, profile)

        if enable != last_state:
            if enable:
                STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
                STATE_FILE.touch()
                print(f"power_monitor: screensaver enabled (AC={on_ac}, profile={profile})")
            else:
                try:
                    STATE_FILE.unlink()
                except FileNotFoundError:
                    pass
                print(f"power_monitor: screensaver disabled (AC={on_ac}, profile={profile})")
            last_state = enable

        time.sleep(POLL_INTERVAL)


if __name__ == "__main__":
    main()