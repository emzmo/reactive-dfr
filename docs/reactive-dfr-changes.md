# From `not-quite-tiny-dfr` to `reactive-dfr` — Change Report

This document describes every change made to
`seojoonlee-dev/not-quite-tiny-dfr` to produce our `reactive-dfr`
fork.

`not-quite-tiny-dfr` is itself a fork of AsahiLinux's `tiny-dfr` — a
Rust daemon that renders buttons onto the Touch Bar DRM device. It
handles touch input, media keys, sliders, and theming, but shows a
**static** set of buttons that doesn't change per application.

`reactive-dfr` extends it with **contextual switching** (buttons change
per app), **screensaver mode**, **S3 suspend/resume hardening**, and
**session environment passing** so widget scripts work from a system
service context.

---

## Line Count Comparison

| File | not-quite-tiny-dfr | reactive-dfr | Delta |
|---|---|---|---|
| `main.rs` | 3991 | 4256 | +265 |
| `backlight.rs` | 250 | 312 | +62 |
| `config.rs` | 1123 | 1151 | +28 |
| `media.rs` | 1343 | 1362 | +19 |
| `widget.rs` | 506 | 521 | +15 |
| `uinput.rs` | 114 | 119 | +5 |
| `button.rs` | 1168 | 1169 | +1 |
| `user.rs` | 82 | 82 | 0 (rebrand only) |
| `display.rs` | 213 | 213 | identical |
| `render.rs` | 570 | 570 | identical |
| `style.rs` | 404 | 404 | identical |
| `sensors.rs` | 165 | 165 | identical |
| `gpu.rs` | 185 | 185 | identical |
| `pixel_shift.rs` | 107 | 107 | identical |
| **Total Rust** | **10221** | **10616** | **+395** |
| **context-daemon/** | — | 43 files | **entirely new** |

7 of 14 Rust source files are **byte-identical** to the upstream fork.
All changes are in 7 files, plus an entirely new Python component.

---

## Change 1: Rebranding (`not-quite-tiny-dfr` → `reactive-dfr`)

**Scope:** All 14 Rust files + Cargo.toml

Mechanical rename of every path, env var, and log message:

| Before | After |
|---|---|
| `~/.config/not-quite-tiny-dfr/` | `~/.config/reactive-dfr/` |
| `/etc/not-quite-tiny-dfr/` | `/etc/reactive-dfr/` |
| `/usr/share/not-quite-tiny-dfr/` | `/usr/share/reactive-dfr/` |
| `NOT_QUITE_TINY_DFR_USER` env var | `REACTIVE_DFR_USER` |
| `~/.cache/not-quite-tiny-dfr/` | `~/.cache/reactive-dfr/` |
| `seat-touchbar` (libinput seat) | `seat1` (D-Bus safe, no hyphen) |
| Binary name `not-quite-tiny-dfr` | `reactive-dfr` |
| All `eprintln!("not-quite-tiny-dfr: ...")` | `eprintln!("reactive-dfr: ...")` |

The seat name change from `seat-touchbar` to `seat1` was necessary
because hyphens in seat names break SDDM's D-Bus path parsing on some
systemd versions.

**No logic change** — this is pure renaming.

---

## Change 2: Screensaver Mode (entirely new)

**Files:** `main.rs` (+180), `config.rs` (+28), `backlight.rs` (+30),
`uinput.rs` (+5)

This is the largest feature addition. `not-quite-tiny-dfr` has no
concept of idle/screensaver — the Touch Bar either shows buttons or
dims/turns off. `reactive-dfr` adds a third state: **screensaver**.

### Config fields (`config.rs`)

Three new TOML fields:

```toml
ScreensaverTimeout = 30       # seconds of Touch Bar idle before screensaver
ScreensaverBrightness = 100   # fixed brightness (0-255) during screensaver
ScreensaverLayer = [ ... ]    # buttons to show during screensaver
```

A new button action `ExitScreensaver` exits the screensaver on tap.

### State machine (`main.rs`)

```rust
enum ScreensaverState {
    Normal,
    Screensaver,
}
```

The daemon tracks **Touch Bar idle time** separately from system-wide
input idle time. The screensaver activates when:

1. `screensaver_timeout > 0` (configured)
2. A state file exists at
   `~/.config/reactive-dfr/state/screensaver_enabled` (the power
   monitor creates/removes this)
3. Touch Bar has been idle for `screensaver_timeout` seconds

When entering screensaver:
- The current layer index is saved (`prev_active_layer`)
- The screensaver layer is appended to `layers` and becomes active
- A complete redraw is triggered

When exiting (via `ExitScreensaver` button or fn key):
- The screensaver layer is popped back to `screensaver_layer`
- The active layer returns to `prev_active_layer`
- The idle timer resets

### Dim/off suppression (`backlight.rs`)

A new `disable_dim_off` flag on `BacklightManager`:

- When `true`: dim and off timeouts are treated as 0 (disabled)
- The screensaver logic sets this flag every frame when the state file
  exists
- This prevents the bar from dimming/turning off before the screensaver
  can activate (the bug we fixed in commit `5c5e269`)

New methods on `BacklightManager`:
- `set_disable_dim_off(bool)` — toggle the flag
- `reset_activity()` — reset the idle timer (used on screensaver exit)
- `last_active()` — expose the last activity instant

### Hot-transition polling

While in screensaver mode, the daemon polls the state file every 5
seconds. If the power monitor removes it (e.g., switched to battery +
power-saver), the daemon exits screensaver and starts the normal
dim/off timer from zero.

### `update_backlight` signature change

```rust
// Before:
pub fn update_backlight(&mut self, cfg: &Config)
// After:
pub fn update_backlight(&mut self, cfg: &Config, touchbar_idle_ms: u64)
```

The idle time is now passed in from `main.rs` using the Touch Bar-only
timer, not the system-wide `last_active` (which resets on keyboard/
mouse input and would prevent the screensaver from ever activating
while you type).

### `ExitScreensaver` in uinput (`uinput.rs`)

The `ExitScreensaver` action is a no-op in the virtual keyboard — it
doesn't emit a key. The actual state transition is handled in `main.rs`
after `toggle_keys` returns. The match arm just prevents the action
from being treated as an unknown key event.

### Screensaver layer widget IDs

The screensaver layer is built using the **same `Widgets` struct** and
ID sequence as the regular layers. This is critical: the
`WidgetRuntime` must know about the screensaver's Command widgets
(e.g., the feeder) to run their scripts. If built with a separate
Widgets/next_id, the widget IDs collide and the runtime never executes
the screensaver commands.

On config hot-reload, the screensaver layer is rebuilt from the new
config. If currently in screensaver mode, the transition is seamless —
the rebuilt layer replaces the old one without disrupting the display.

---

## Change 3: S3 Suspend/Resume Hardening

**Files:** `main.rs` (+23), `backlight.rs` (+32)

`not-quite-tiny-dfr` assumes the DRM card and backlight sysfs are
always present. On T1 hardware, S3 suspend/resume resets the iBridge
USB device, causing both to disappear for several seconds. The
upstream daemon panic-loops via `Restart=always`, flooding the journal.

### DRM card retry loop (`main.rs`)

```rust
let mut drm = None;
for attempt in 1..=30 {
    match DrmBackend::open_card() {
        Ok(card) => { drm = Some(card); break; }
        Err(e) => {
            std::thread::sleep(std::time::Duration::from_secs(2));
        }
    }
}
```

Retries for up to 60 seconds (30 attempts × 2s). If the card never
appears, the daemon exits cleanly with a message (not a panic).

### Backlight write failure → graceful exit (`backlight.rs`)

```rust
if let Err(e) = file.write_all(...) {
    eprintln!("reactive-dfr: backlight write failed: {e}, exiting for restart");
    std::process::exit(1);
}
```

When the backlight sysfs file disappears (USB reset), writing to it
fails. Instead of panicking, the daemon exits with code 1 so
`Restart=always` + the retry loop brings it back with fresh file
descriptors.

### BacklightManager fallback (`backlight.rs`)

`BacklightManager::new()` now handles missing backlight devices
gracefully:

- If `find_backlight()` fails → falls back to `/dev/null` with safe
  defaults (max=255, current=128)
- If the sysfs file can't be opened → same fallback
- The daemon starts and retries via `Restart=always` rather than
  panic-looping

---

## Change 4: Session Environment Passing

**Files:** `main.rs` (+29), `media.rs` (+19), `widget.rs` (+15)

`not-quite-tiny-dfr` runs as a user session service where `HOME`,
`DBUS_SESSION_BUS_ADDRESS`, `WAYLAND_DISPLAY`, and
`XDG_RUNTIME_DIR` are already set. `reactive-dfr` runs as a **system
service** where none of these are in the initial environment.

### `drop_privileges` (`main.rs`)

After dropping to the target user, the daemon now sets:

- `HOME` — from the resolved user's home directory
- `XDG_RUNTIME_DIR` — `/run/user/<uid>`
- `DBUS_SESSION_BUS_ADDRESS` — `unix:path=/run/user/<uid>/bus`
- `WAYLAND_DISPLAY` — auto-detected by checking which `wayland-*`
  socket exists in XDG_RUNTIME_DIR
- `PATH` — extended with `/usr/local/bin`, `/usr/bin`,
  `~/.local/bin`, `~/.cargo/bin`

These are set via `std::env::set_var` so all child processes (widget
scripts, OnClick commands) inherit them.

### `widget.rs` — HOME for widget commands

`run_command()` now explicitly passes `HOME` to the child `sh`
process, so `~` expansion works in widget command strings like
`python3 ~/feeder.py`.

### `media.rs` — session env for OnClick commands

`run_tap_command()` now passes `HOME`, `DBUS_SESSION_BUS_ADDRESS`,
`WAYLAND_DISPLAY`, and `XDG_RUNTIME_DIR` to OnClick child processes,
so `xdg-open`, `wl-copy`, and other session tools work from the
daemon's context.

---

## Change 5: Volume Slider Mute Toggle on Icon Tap

**Files:** `main.rs` (+15 in touch handling)

`not-quite-tiny-dfr` treats a tap on the slider icon cap as a slider
drag start. `reactive-dfr` distinguishes between a tap and a drag:

- `SliderDrag` now carries `started_on_icon: bool`
- On **touch-up**: if `started_on_icon` is true and there was no
  movement (a clean tap), the slider's `SliderMute` command is
  invoked with `"toggle"`
- This lets you mute/unmute by tapping the volume icon, without
  moving the slider

The dynamic volume icon (showing `volume_up` / `volume_down` /
`volume_off` based on level) was also added so the icon reflects the
current state.

---

## Change 6: Deferred Login Screensaver Path Fix

**Files:** `main.rs` (+5)

The `screensaver_state_file` path is set from `target_user` before the
deferred login resolves the user. When the daemon starts before anyone
is logged in (common on boot), `target_user` is `None` and the path
falls back to `/tmp/reactive-dfr-screensaver-enabled`, which never
matches the real state file.

Fix: `screensaver_state_file` is now `mut` and updated in the
deferred-login block, right after `drop_privileges`, using the
resolved user's home directory.

---

## Change 7: Layer Restructure

**Files:** `main.rs` (config loading logic)

`not-quite-tiny-dfr` loads all layers from a single config file.
`reactive-dfr` restructures layers to support contextual switching:

| Layer | Content | Source |
|---|---|---|
| 0 | Context buttons + minipanel (volume, brightness, kbd backlight) | Generated by context-daemon |
| 1 | F-keys (F1–F12, shown when fn held) | Fixed in `base.toml` |
| 2 | System monitor (CPU, GPU, battery, time, IP, widgets) | Fixed in `base.toml` |

Layer 0 is **replaced** on every app switch (the context-daemon
regenerates `config.toml`). Layers 1+ are fixed and come from
`base.toml`. The minipanel is appended to layer 0 by the composer and
is configurable in `base.toml`'s `Minipanel` key.

---

## Change 8: Context Daemon (entirely new component)

**Directory:** `context-daemon/` (43 files, not in upstream at all)

This is the defining feature of `reactive-dfr` — the "reactive" part.
It is a Python daemon that watches the compositor and generates the
config the Rust daemon reads.

### Architecture

```
Hyprland socket2 ──→ daemon.py ──→ matcher.py ──→ contexts/*.toml
                         │
                         ▼
                    composer.py (merges base.toml + context + minipanel)
                         │
                         ▼
                    ~/.config/reactive-dfr/config.toml
                         │
                         ▼
                    reactive-dfr (Rust daemon, hot-reloads via inotify)
```

### Components

| File | Purpose |
|---|---|
| `daemon.py` | Main loop — watches compositor, triggers config generation |
| `composer.py` | TOML merger — base + context buttons + minipanel → config.toml |
| `matcher.py` | Regex matching of window class → context name |
| `backends/hyprland.py` | Hyprland socket2 watcher (with reconnection) |
| `backends/sway.py` | Sway IPC backend |
| `backends/base.py` | Abstract backend interface |
| `scripts/power_monitor.py` | AC/battery + power profile → screensaver enable/disable |
| `widgets/feeder.py` | Rotating info feeder (RSS, crypto, calendar, mail) |
| `widgets/feeder_click.sh` | OnClick helper — escapes daemon sandbox via setsid |

### Config files

| File | Purpose |
|---|---|
| `config/base.toml` | Base config — layers, screensaver, minipanel, style |
| `config/matcher.toml` | Window class → context mapping |
| `config/contexts/*.toml` | 14 per-app button definitions (terminal, browser, IDE, etc.) |

### Service templates

| File | Purpose |
|---|---|
| `systemd/touchbar-power-monitor.service` | User service for power monitor |
| `systemd/recorder-sync.service.template` | USB sync service template |
| `udev/99-usb-sync.rules.template` | USB sync udev rule template |

---

## What Was NOT Changed

These 7 files are **byte-identical** to `not-quite-tiny-dfr`:

| File | Purpose |
|---|---|
| `display.rs` | DRM card discovery, atomic commits, framebuffer |
| `render.rs` | Cairo rendering (text, icons, sliders) |
| `style.rs` | Style config (colors, fonts, sizes) |
| `sensors.rs` | CPU/GPU/battery temperature sensors |
| `gpu.rs` | GPU temperature reader |
| `pixel_shift.rs` | OLED burn-in prevention |
| `crash_bitmap.raw` | Crash screen bitmap |

The rendering engine, display backend, style system, and sensor reading
are completely unchanged from upstream.

---

## Commit History

| Commit | Description |
|---|---|
| `474b53b` | feat: unify reactive-dfr (daemon + context-daemon) |
| `8de898d` | docs: add README.md |
| `97e0e5f` | refactor: unify config paths to reactive-dfr |
| `266d2c3` | fix: harden error handling and systemd sandboxing |
| `bc7478a` | fix: use seat1 (no hyphen, D-Bus safe) |
| `3a84689` | docs: add comprehensive project report |
| `4c7e735` | feat: add PKGBUILD for AUR |
| `8252f1b` | feat: add split PKGBUILD (driver + daemon) |
| `c22bd72` | fix: survive S3 suspend/resume without panic-looping |
| `3487f23` | refactor: unify all config under ~/.config/reactive-dfr/ |
| `24f9d0f` | feat: dynamic volume icon and mute toggle on icon tap |
| `b84b64b` | feat: restructure layers with fixed minipanel and fn-key support |
| `ba74e78` | feat: add generic USB sync template |
| `c3398e3` | feat: add Screensaver mode triggered by Touch Bar inactivity |
| `76e0454` | feat: add power monitor for screensaver AC/battery toggle |
| `0f95eac` | fix: use touchbar idle timer for dim/off and hot-transition |
| `054830c` | feat: add customizable feeder widget for screensaver |
| `1eb7006` | fix: pass user environment to widget and OnClick commands |
| `3faa799` | fix: feeder OnClick helper to escape daemon sandbox |
| `5c5e269` | fix: screensaver state file path after deferred login |
| `cd53bf5` | refactor: move minipanel config to base.toml |
| `d01e35d` | docs: add MIT license and contributing guidelines |
| `7c916f5` | chore: update service paths after repo reorganization |
| `8e9a9c9` | docs: add plain-language explanation of the full stack |

---

## Credits

`reactive-dfr` builds on:
- **AsahiLinux/tiny-dfr** — the original Touch Bar renderer
- **seojoonlee-dev/not-quite-tiny-dfr** — the fork we extended, which
  added T2 display-stream stall workarounds
- **Seborider/mbp-t1-touchbar** — T1 protocol fixes that informed our
  kernel driver work

The Rust render engine (7 unchanged files) is entirely their work.
Our contributions are the screensaver mode, S3 hardening, session
environment passing, contextual switching (the Python context daemon),
and the integration work to make it all run reliably on T1 hardware
as a system service.