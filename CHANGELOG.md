# Changelog — reactive-dfr

All notable changes to this project are documented here.
The format is based on [Keep a Changelog](https://keepachangelog.com/).

---

## [v2.0.0] — 2026-10-26

### Added
- **Chip type detection**: the daemon reads `/sys/class/drm/cardN/device/
  mac_type` at startup to detect T1 vs T2 hardware. T2-specific workarounds
  (heartbeat flush, full-bar redraw promotion) are disabled on T1, freeing
  USB 2.0 bandwidth. Falls back to conservative behavior (all workarounds
  active) if the attribute is missing.
- **Adaptive FPS**: the daemon now adapts its frame rate based on
  interaction state:
  - 60fps during touch interaction (scroll, slider, animation)
  - 15fps for widget-only updates (feeder, CPU, clock)
  - 5fps settle for 1s after interaction ends
  - 0fps full idle (timer unset, epoll blocks — existing behavior preserved)
- **Flush error recovery**: tracks consecutive `drm.dirty()` failures and
  exits after 3 in a row, so `Restart=always` + the `open_card` retry loop
  can recover from USB reset (S3 suspend/resume scenario).
- **install.sh**: universal installer for any distro (builds with cargo,
  installs binary + assets + context daemon + config + services + udev +
  deploys user config/widgets).
- **PKGBUILD**: Arch package with `build()` (cargo) and `package()` that
  installs all components to system paths.
- **reactive-dfr-setup**: user-config deployment script (copies config
  and widgets to `~/.config/reactive-dfr/`, enables user services).
- **Install hooks** (`reactive-dfr.install`): post-install/upgrade/remove
  hooks with user instructions.
- **known-issues.md**: post-v1 audit with 6 issues, technical analysis of
  the render loop, USB bandwidth, dirty rects, and profiling infrastructure.
- **Profiling documentation**: README section documenting `NQTD_FRAME_LOG=1`
  and `NQTD_TOUCH_LOG=1` with example output and enable instructions.
- **Change report** (`docs/reactive-dfr-changes.md`): detailed analysis of
  all changes from `not-quite-tiny-dfr` to this fork.
- **How-it-works doc** (`docs/how-it-works.md`): plain-language explanation
  of the full Touch Bar stack, from hardware to screensaver.

### Changed
- **touchbar-power-monitor.service**: updated to use `/usr/lib/reactive-dfr/`
  paths (was `~/Projects/` dev path).
- **touchbar-ctx.service**: clean template added with `/usr/lib/reactive-dfr/`
  paths for packaged installs.
- **10 context configs** converted from old `PrimaryLayerKeys` format to
  `[[layer]]` format (aseprite, clipboard, comms, files, gaming, gimp, ide,
  screenshot, system, virtual-desktops).
- **Udev rules updated**: `99-touchbar-not-quite-tiny-dfr.rules` renamed to
  `99-touchbar-reactive-dfr.rules`, systemd aliases updated from
  `not_quite_tiny_dfr_*` to `reactive_dfr_*`. Seat rule updated from
  `seat-touchbar` to `seat1`.
- **README installation section** rewritten with 3 methods (script, manual,
  PKGBUILD).
- **Dimming LUT cached**: the 256-entry lookup table for software brightness
  scaling is now cached and only rebuilt when the dim factor changes
  between frames, instead of being recomputed every frame.

### Fixed
- **Touch_down 60fps transition**: added `!touches.is_empty()` to the
  `is_interacting` and `frame_pending` checks so the daemon transitions
  to 60fps instantly on touch_down, before gesture recognition. Fixes
  stutter at the start of two-finger swipes.
- **Screensaver state file path**: updated after deferred login (was
  pointing to a `/tmp` fallback when the daemon started before login).
- **User environment passing**: `drop_privileges` now sets HOME,
  XDG_RUNTIME_DIR, DBUS_SESSION_BUS_ADDRESS, WAYLAND_DISPLAY, and
  extends PATH. Widget and OnClick commands inherit these so
  `python3 ~/feeder.py` and `xdg-open` work from the daemon's context.

### Removed
- **Legacy `touchbar-ctx.py` CLI**: stale, used old format and paths.
- **Legacy `touchbar-daemon.service.in`**: superseded by the clean
  `touchbar-ctx.service` template.
- **Stale `context-daemon/install.sh`**: Spanish, referenced old paths,
  missing power_monitor. Replaced by the root-level `install.sh`.
- **Stale `PKGBUILD`** (split package with appletbdrm-t1): replaced by
  reactive-dfr-only PKGBUILD.
- **Stale `REPORT.md`**: moved to touchbar-research.

---

## [v1.0.0] — 2026-10-17

### Added
- **Project unification**: merged the Rust render engine (forked from
  `not-quite-tiny-dfr`) and the Python context daemon into one repo.
- **Contextual switching**: the Python context daemon watches Hyprland
  (socket2) or Sway (IPC) for window changes, matches the active window
  to a context, and composes a new `config.toml` by merging `base.toml` +
  context buttons + minipanel. The Rust daemon hot-reloads via inotify.
- **14 context configs**: terminal, browser, ide, media, files, gaming, comms,
  gimp, aseprite, clipboard, screenshot, system, virtual-desktops, default.
- **Screensaver mode**: after configurable idle timeout, the Touch Bar
  switches to a screensaver layer with esc, feeder widget, and exit
  button. State file controlled by the power monitor.
- **Feeder widget**: rotating info display (RSS news via feedparser, crypto
  via CoinGecko, calendar via khal, mail placeholder). Rotates every 5s,
  caches 10min. OnClick opens URL via `feeder_click.sh` (escapes daemon
  sandbox via `setsid`).
- **Power monitor**: watches AC/battery + power profile, toggles
  `screensaver_enabled` state file based on a matrix
  (battery + power-saver = disabled).
- **Layer restructure**: layer 0 = context + minipanel (volume/brightness/
  kbd_backlight sliders), layer 1 = F-keys (fn), layer 2 = system monitor.
- **Minipanel**: configurable in `base.toml` (was hardcoded in composer.py).
- **USB sync template**: recorder_sync.sh.template + udev rule + systemd
  service for USB device sync indicator.
- **S3 suspend/resume hardening**: DRM card open retry loop (60s),
  backlight write failure → exit(1), BacklightManager fallback to
  `/dev/null` when sysfs is missing.
- **Volume slider mute toggle**: tapping the volume icon toggles mute
  (was treated as slider drag start). Dynamic volume icon (up/down/off).
- **Widget scripts**: cpu.sh, cpu_expand.sh, ip.sh, ip_expand.sh, copy_ip.sh,
  uptime.sh, feeder_debug.sh added to the repo.
- **MIT license** and **CONTRIBUTING.md**.
- **README.md** with project overview and requirements.
- **PKGBUILD** for AUR.

### Changed
- **Rebranded** from `not-quite-tiny-dfr` to `reactive-dfr`: all paths, env
  vars, log messages, seat name (`seat-touchbar` → `seat1`).
- **Config unified** under `~/.config/reactive-dfr/` (was scattered across
  `not-quite-tiny-dfr` and `touchbar-daemon` dirs).
- **Feeder state/action files** moved to `$CACHE_DIRECTORY`
  (`/var/cache/reactive-dfr`) to avoid `/tmp` permission issues.
- **Systemd sandboxing** hardened: `NoNewPrivileges`, `ProtectSystem=strict`,
  `ProtectHome=read-only`, etc.

### Fixed
- **Touchbar idle timer**: dim/off now uses Touch Bar-only idle time
  (`last_touchbar_interaction`), not system-wide input (`last_active`),
  so typing on the physical keyboard doesn't prevent the screensaver.
- **Hot-transition**: while in screensaver, polls the state file every 5s
  and exits screensaver if it was removed (e.g., by the power monitor
  switching to battery).
- **feeder OnClick**: uses `feeder_click.sh` helper with `setsid` to
  escape the daemon sandbox (`xdg-open` and `systemd-run --user` fail
  from `NoNewPrivileges=true` context).

---

## [baseline] — pre-fork

Based on `seojoonlee-dev/not-quite-tiny-dfr` (v0.3.7), which forked from
`AsahiLinux/tiny-dfr`. The Rust render engine (7 of 14 source files) is
byte-identical to the upstream fork. All changes are in 7 files plus an
entirely new Python context daemon.

[v2.0.0]: https://github.com/emzmo/reactive-dfr/releases/tag/v2.0.0
[v1.0.0]: https://github.com/emzmo/reactive-dfr/releases/tag/v1.0.0