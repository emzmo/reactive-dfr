# Project Report: reactive-dfr — Touch Bar on Linux for MacBook Pro T1

**Date**: 2026-10-10  
**Hardware**: MacBook Pro 14,2 (2017, Intel Kaby Lake, Apple T1 chip, iBridge 05ac:8600)  
**OS**: Arch Linux (Omarchy), kernel 7.2.5-3-omarchy  
**Compositor**: Hyprland (Wayland)

---

## 1. Executive Summary

This project brought the Touch Bar on a 2017 MacBook Pro (T1 chip) to full
functionality on Linux — display rendering, touch input, contextual switching,
and interactive widgets. The Touch Bar now adapts to the active window
automatically, showing contextual controls for each application.

The work involved three layers: a patched kernel DRM driver (appletbdrm), a
Rust render daemon (reactive-dfr, forked from not-quite-tiny-dfr), and a
Python context daemon that watches Hyprland for window changes.

---

## 2. Repositories

| Repo | URL | Purpose |
|------|-----|---------|
| appletbdrm-t1 | https://github.com/emzmo/appletbdrm-t1 | Kernel DRM driver with T1 dialect fixes |
| reactive-dfr | https://github.com/emzmo/reactive-dfr | Rust daemon + Python context daemon (unified) |

---

## 3. Kernel Driver: appletbdrm T1 Fixes

The mainline `appletbdrm` driver (Linux 6.15+) only supports T2 Macs
(05ac:8302). The T1 iBridge (05ac:8600) uses the same DRM protocol but with
three dialect differences that required patches.

### Commits (appletbdrm-t1, branch t1-dialect-fixes)

| Commit | Description |
|--------|-------------|
| `ef655a4` | Replace `drm_atomic_state` with `drm_atomic_commit` for kernel 7.x API |
| `adec78a` | Clear stale bulk pipes before T1 probe (`usb_clear_halt`) |
| `9da3516` | Switch T1 from async URB to sync probe (avoid -EAGAIN on submit) |
| `e0ddfc1` | Drain 16-byte T1 preamble on bulk reads (loop of 8 attempts) |
| `a88f740` | Gate timestamp check for T1 one-behind ACK scheme |
| `f5244a7` | DKMS: build only kernel module, skip ibridge-switcher userspace |
| `02a57b5` | systemd: auto-switch iBridge to USB config 2 on boot |
| `22af2cb` | systemd: increase config switch wait to 25s |
| `530f42b` | systemd: use readlink for DRM driver symlink check |
| `7998179` | udev: assign Touch Bar to its own seat for daemon isolation |
| `babe187` | chore: clean up repo, ignore external repos |
| `a55496a` | fix: use seat1 instead of seat-touchbar (D-Bus path crash) |

### T1 Protocol Dialect Fixes (ported from Seborider/mbp-t1-touchbar)

1. **Stale pipe clearing**: T1 can enumerate with bulk pipes halted from
   USB config 1. `usb_clear_halt()` on both pipes before first transfer.
2. **16-byte preamble drain**: T1 prefixes bulk replies with a short
   transfer. `read_response()` loops up to 8 times, draining short transfers.
3. **One-behind ACK**: T1 acknowledges frame N-1, not frame N. Timestamp
   check in `flush_damage()` gated on `mac_type != MAC_TYPE_T1`.
4. **Sync probe**: Replaced async URB (which failed with -EAGAIN) with
   synchronous `usb_bulk_msg` path, matching Seborider's approach.

### DKMS Modules Installed

| Module | Version | Purpose |
|--------|---------|---------|
| appletbdrm | 1.2 | DRM display driver (T1 + T2) |
| kernel-hid-t1 | 0.2 | hid-multitouch with T1 device ID (05ac:8600) |

---

## 4. Rust Daemon: reactive-dfr

Forked from `not-quite-tiny-dfr` (by seojoonlee-dev, which forked from
`tiny-dfr` by AsahiLinux). The Rust daemon communicates with the kernel via
DRM and libinput to render the Touch Bar UI and handle touch events.

### T1-Specific Changes

1. **Digitizer name match** (`src/main.rs`): Added
   `|| dev.name().contains("iBridge Touchpad")` to the digitizer identification
   check. The T1's digitizer is named "Apple Inc. iBridge Touchpad" — upstream
   only matched " Touch Bar" (T2/Apple Silicon).

2. **systemd unit** (`etc/systemd/system/reactive-dfr.service`): Added
   `After=ibridge-config-switch.service` and `Requires=ibridge-config-switch.service`
   so the daemon starts after the USB config switch completes.

### Feature Additions

3. **OnClick shell commands for Command widgets** (`src/button.rs`,
   `src/main.rs`): Upstream only supported shell-command OnClick for Media
   widgets. Added `tap_command: Option<String>` field to the Button struct,
   extraction in the config loader, and execution in both `Held` and
   `Pending` touch-up handlers.

4. **highlight_on_tap for Command widgets** (`src/main.rs`): Extended the
   highlight check to include `OnClick::Command(_)` so buttons with shell
   commands light up on tap (was only true for `OnClick::Action`).

### Config Path Unification

All paths changed from `not-quite-tiny-dfr` to `reactive-dfr`:
- Binary: `/usr/bin/reactive-dfr`
- Config: `~/.config/reactive-dfr/config.toml`
- Share: `/usr/share/reactive-dfr/`
- Cache: `/var/cache/reactive-dfr/`
- Env var: `REACTIVE_DFR_USER`

---

## 5. Python Context Daemon

Watches Hyprland's `.socket2.sock` for `activewindow` events. When the active
window changes, composes a new TOML config and writes it atomically to
`~/.config/reactive-dfr/config.toml`. The Rust daemon detects the change via
inotify and hot-reloads instantly.

### Architecture

- `matcher.py`: Maps window class/title to context name (from `matcher.toml`)
- `composer.py`: Merges `base.toml` (global + fixed layers) with the active
  context's `[[layer]]` (replaces layer 0), serializes with `tomli_w`
- `daemon.py`: Event loop, Hyprland socket watcher with reconnection
- `backends/hyprland.py`: `hyprctl -j activewindow` + socket2 events

### Contexts

| Context | Trigger | Layer 0 content |
|---------|---------|-----------------|
| default | No match | F1-F12 |
| browser | Firefox, Chromium, Zen, etc. | Navigation (back, forward, reload, tabs) |
| terminal | foot, kitty, alacritty, etc. | Signals (^C, ^D, ^Z), clear, history |
| media | Spotify, mpv, VLC, etc. | Play/pause, volume slider, brightness |
| 11 others | Various apps | Fall back to default (pending update) |

### Fallback

Contexts using the old `PrimaryLayerKeys` format (no `[[layer]]` key)
automatically fall back to `default.toml` so the Touch Bar never shows an
empty layer.

---

## 6. Systemd Services

### System Services

| Service | Type | Purpose |
|---------|------|---------|
| `ibridge-config-switch.service` | oneshot | Switch iBridge USB config 1→2 at boot |
| `reactive-dfr.service` | simple | Rust render daemon (DRM + libinput) |

### User Services

| Service | Type | Purpose |
|---------|------|---------|
| `touchbar-ctx.service` | simple | Python context daemon (Hyprland IPC) |

### Sandboxing

**reactive-dfr.service**: NoNewPrivileges, ProtectSystem=strict,
ProtectHome=read-only, PrivateTmp, PrivateIPC, ProtectKernelTunables/Modules/Logs,
ProtectControlGroups=strict, RestrictAddressFamilies=AF_UNIX AF_NETLINK AF_INET AF_INET6,
RestrictNamespaces, RestrictSUIDSGID, CacheDirectory.

**touchbar-ctx.service**: NoNewPrivileges, ProtectSystem=strict,
ProtectHome=read-only, ReadWritePaths=~/.config/reactive-dfr, PrivateTmp,
ProtectKernelTunables/Modules/Logs, RestrictAddressFamilies=AF_UNIX AF_NETLINK,
RestrictNamespaces, RestrictRealtime.

---

## 7. udev Rules

### `/etc/udev/rules.d/99-touchbar-seat.rules`

```
# DRM card: skip all seat tags (GOTO seat_end)
# Daemon finds it by aspect ratio (height/width >= 30)
SUBSYSTEM=="drm", ATTRS{idVendor}=="05ac", ATTRS{idProduct}=="8600", GOTO="seat_end"

# Digitizer: assign to seat1 (D-Bus safe, no hyphen)
SUBSYSTEM=="input", ATTRS{idVendor}=="05ac", ATTRS{idProduct}=="8600", ENV{ID_SEAT}="seat1"
```

### Design Decision: seat1 vs seat-touchbar

The initial approach used `ID_SEAT="seat-touchbar"` for both DRM and input
devices. This caused a critical bug: the hyphen in `seat-touchbar` is illegal
in D-Bus object paths. SDDM builds a path
`/org/freedesktop/DisplayManager/Seat-touchbar` which fails with
`QDBusObjectPath: invalid path`. On most boots SDDM logs the error and
continues, but on cold boot it can cause Hyprland to crash with
`XDG_RUNTIME_DIR is not set!` (signal 6/ABRT), leaving the user on a black
screen.

Fix: DRM card gets no seat at all (`GOTO="seat_end"`), digitizer gets
`ID_SEAT="seat1"` (valid logind name, no hyphen, D-Bus safe).

---

## 8. Boot Sequence

```
t=0s    Kernel boot, iBridge appears in USB config 1 (keyboard mode)
t=15s   appletbdrm DKMS module loaded
t=16s   ibridge-config-switch.service: echo 2 > bConfigurationValue
t=16s   USB re-enumeration → appletbdrm probes T1 → "Touch Bar initialized"
t=16s   /dev/dri/card0 created, appletb_backlight registered
t=27s   reactive-dfr.service starts → DRM master, libinput seat1
t=27s   touchbar-ctx.service starts → Hyprland socket2 connected
t=29s   Context applied (terminal/default based on active window)
```

All services load automatically. No manual intervention required.

---

## 9. Widgets and Interactivity

### Built-in Widgets

| Widget | Type | Description |
|--------|------|-------------|
| Cpu | built-in | CPU temperature (celsius/fahrenheit/watts) |
| Gpu | built-in | GPU temperature (auto-detects Intel/AMD/NVIDIA) |
| Battery | built-in | Battery icon + percentage |
| Time | built-in | Clock (strftime format) |
| Media | built-in | MPRIS transport controls + album art + lyrics |

### Custom Script Widgets

| Widget | Script | Interval | OnClick |
|--------|--------|----------|---------|
| IP address | `ip.sh` | 30s | `copy_ip.sh` (wl-copy to clipboard) |
| CPU usage | `cpu.sh` | 3s | Expand: `cpu_expand.sh` (load, top processes) |
| Uptime | `uptime.sh` | 60s | — |
| Battery % | `battery.sh` | 30s | — |

### Volume Slider

Interactive slider using `wpctl` (PipeWire):
- Tap to expand, drag to change volume
- Tap icon to toggle mute
- Polls current volume via `SliderGet`

### JSON Protocol

Scripts output JSON: `{"text":"42°C","color":"#ff5555","icon":"memory"}`
- `text`: label shown on the button
- `color`: hex color for the label
- `icon`: icon name resolved from config directories

---

## 10. Layers

| Layer | Content | Context |
|-------|---------|---------|
| 0 | Context-dependent (F-keys, browser nav, terminal shortcuts, etc.) | Replaced by context daemon |
| 1 | Media keys + volume slider | Fixed |
| 2 | System monitor (CPU, GPU, battery, clock, IP, CPU usage) | Fixed |
| 3 | Clock + date | Fixed |

Two-finger horizontal swipe cycles between layers. Scroll within layers
that have more buttons than fit.

---

## 11. Audit Findings

### Bugs Found and Fixed

| Severity | Finding | Fix |
|----------|---------|-----|
| Critical | `seat-touchbar` D-Bus path crash on cold boot | Renamed to `seat1`, DRM card to no-seat |
| Medium | Python daemon stale socket path on Hyprland restart | Re-resolve socket path on each reconnection |
| Low | touchbar-ctx.service no sandboxing | Added ProtectSystem, PrivateTmp, etc. |
| Low | media.toml using old format | Updated to `[[layer]]` with volume slider |

### No Action Needed

| Finding | Reason |
|---------|--------|
| 76 `unwrap()` in Rust daemon | Startup assertions (Restart=always covers) + cairo (non-failing) + mutex (correct behavior) |
| Hot-reload memory | WidgetRuntime Drop properly stops old threads |
| Atomic writes | composer.py uses tempfile + os.replace |
| 11 old context files | Fallback to default (F-keys), safe |

### Stress Test Results

- 10 config reloads: no panics, memory stable (13.5M)
- Window switching: context daemon switches correctly, memory stable (10.3M)
- Cold boot: all services load automatically, no errors

---

## 12. Known Issues

1. **snd_hda_macbookpro DKMS broken**: `dkms status` reports
   `snd_hda_macbookpro/0.1: broken` (missing source directory). This is a
   pre-existing issue unrelated to this project. Audio works via the in-tree
   snd_hda_intel driver.

2. **Apple SPI Touchpad libinput warnings**: `kernel bug: Touch jump detected
   and discarded` — known kernel bug with the SPI trackpad, not related to the
   Touch Bar. Does not affect functionality.

3. **11 context files using old format**: aseprite, gimp, ide, files, comms,
   gaming, screenshot, system, clipboard, virtual-desktops — all fall back to
   default (F-keys). Pending update to `[[layer]]` format.

4. **Double LUKS prompt on reboot**: Caused by `resume=/dev/mapper/omarchy_root`
   (swapfile on encrypted BTRFS). Normal behavior, unrelated to this project.

5. **Camera unavailable in config 2**: The iBridge USB config 2 (DRM mode)
   does not expose the UVC webcam interface. Camera and Touch Bar display are
   mutually exclusive. This is a hardware limitation of the T1 chip.

---

## 13. Files Installed on System

### Kernel (DKMS)

```
/usr/src/appletbdrm-1.2/          — DRM driver source (DKMS)
/usr/src/kernel-hid-t1-0.2/       — hid-multitouch T1 patch (DKMS)
/usr/lib/modules/.../updates/dkms/appletbdrm.ko.zst
/usr/lib/modules/.../updates/dkms/hid-multitouch.ko.zst
```

### Binaries

```
/usr/bin/reactive-dfr             — Rust render daemon
/usr/local/sbin/ibridge-config-switch.sh — USB config switch script
```

### Systemd

```
/etc/systemd/system/ibridge-config-switch.service  — USB config switch (enabled)
/etc/systemd/system/reactive-dfr.service           — Render daemon (enabled)
~/.config/systemd/user/touchbar-ctx.service        — Context daemon (enabled)
```

### udev

```
/etc/udev/rules.d/99-touchbar-seat.rules  — Touch Bar seat isolation
```

### Config and Assets

```
/usr/share/reactive-dfr/           — Default config, SVGs, widget scripts
~/.config/reactive-dfr/            — User config, custom widgets
~/.config/touchbar-daemon/config/  — Context daemon config (base, matcher, contexts)
```

---

## 14. Credits

- **AsahiLinux team** — Original `tiny-dfr` and Apple Silicon reverse engineering
- **seojoonlee-dev** — `not-quite-tiny-dfr` (theming, sliders, scrollable layers, media)
- **Seborider** — T1 USB protocol dialect fixes, `mbp-t1-touchbar` project
- **Kerem Karabay** — Mainline `appletbdrm` and `hid-multitouch` Touch Bar driver
- **Ronald Tschalär** — Original T1 driver work (`apple-ibridge`)

---

## 15. Future Work

- **Update remaining 11 context files** to `[[layer]]` format
- **Game profiles**: Read game state (resources, selections) and display on Touch Bar
- **D-Bus API**: Allow applications to push custom layouts directly
- **More compositor support**: Wayfire, River backends
- **AUR package**: PKGBUILD for automated installation
- **Install script**: `install.sh` for one-command setup
- **NixOS module**: Declarative configuration