# How the Touch Bar Works — From Zero to Screensaver

This document explains, in plain language, how the Touch Bar on a
MacBook Pro 2017 (T1 chip) goes from a blank Linux installation to
showing a screensaver with rotating news, crypto prices, and calendar
events.

No programming knowledge required.

---

## The Hardware

Inside a MacBook Pro 2017 there is a small separate chip called the
**T1** (branded "iBridge"). It is connected to the main processor via a
USB cable (internal, not visible from outside). The T1 controls three
things:

1. The **Touch Bar** — a thin OLED screen with a touch sensor on top
2. The **Touch ID** fingerprint reader
3. The **webcam**

Out of the box, when you boot Linux, the T1 presents itself as a
simple USB keyboard. The Touch Bar screen is dark. Nothing works yet.

The T1 has two **USB configurations** (think of them as "modes"):

- **Config 1 (default):** acts as a keyboard. The Touch Bar is dark.
- **Config 2:** exposes the display and the touch sensor as separate
  devices that Linux can control.

The first thing we need to do is switch the T1 from config 1 to
config 2.

---

## Step 1: The Kernel Driver (`appletbdrm`)

Linux needs a **driver** — a piece of code that knows how to talk to a
specific piece of hardware. Without a driver, Linux sees the T1 but
doesn't know what to do with it.

We install a driver called `appletbdrm`. It is a **DKMS module**,
which means it gets compiled specifically for whatever kernel version
is running, and automatically recompiled when the kernel updates.

Once installed, the driver registers the Touch Bar screen as a **DRM
device**. DRM (Direct Rendering Manager) is Linux's standard system for
managing displays. After the driver loads, the Touch Bar appears as a
file on the system:

```
/dev/dri/card0
```

To Linux, the Touch Bar is now just a very small, very wide monitor
(2160 × 68 pixels). Any program that knows how to draw to a DRM
display can send pixels to it.

The driver also handles:
- Sending image data to the OLED panel via USB
- Controlling the backlight (brightness)
- A retry loop at startup (waits up to 60 seconds for the T1 to appear,
  important after suspend/resume)

---

## Step 2: The USB Config Switch (`ibridge-config-switch`)

The driver alone isn't enough — the T1 starts in config 1 (keyboard
mode). We need to flip it to config 2 before the driver can use it.

A small helper program called `ibridge_switcher` does this. It is run
by a systemd service called `ibridge-config-switch.service` that
starts very early in the boot process (right after the USB system is
ready).

**Sequence at boot:**

1. Linux boots, detects the T1 in config 1 (keyboard)
2. `ibridge-config-switch.service` runs `ibridge_switcher`
3. The T1 switches to config 2
4. The Touch Bar display and touch sensor appear as new USB devices
5. The `appletbdrm` driver grabs the display → `/dev/dri/card0` exists
6. A touch sensor device appears → `/dev/input/eventN`

---

## Step 3: The Seat Rule (`99-touchbar-seat.rules`)

Linux has a concept called **seats**. A seat is a group of devices
assigned to a user session. Your main screen, keyboard, and trackpad
belong to `seat0`. Hyprland (the window manager) grabs all display
devices on `seat0`.

The problem: if Hyprland grabs `/dev/dri/card0` (the Touch Bar), our
daemon can't use it. We need Hyprland to ignore the Touch Bar.

We solve this with a **udev rule** (a rule that runs when devices are
detected):

- The **touch sensor** is assigned to `seat1` (a separate seat that
  Hyprland doesn't look at). Our daemon reads touch events from there.
- The **DRM card** uses a trick: a `GOTO` that jumps to the end of the
  default seat rules, so it doesn't get tagged for `seat0`. This means
  Hyprland *might* grab it depending on timing (fragile, but doesn't
  crash the boot — we learned the hard way that assigning it to
  `seat1` crashes the login screen on systemd 262.1).

---

## Step 4: The Daemon (`reactive-dfr`)

Now that the hardware is visible, we need a program that actually
**draws something** on the Touch Bar. That's the `reactive-dfr` daemon,
written in Rust.

It runs as a **system service** (starts at boot, runs in the
background). Here's what it does, in order:

### 4a: Open the display

The daemon opens `/dev/dri/card0` and takes **DRM master** — exclusive
control of the Touch Bar display. It looks through all DRM cards and
finds the Touch Bar by its unusual shape (height/width ratio ≥ 30 — no
normal monitor is that thin).

It opens the card **as root** before dropping privileges to your user.
This is important: it means the daemon can always open the card,
regardless of seat assignments or group permissions.

### 4b: Read touch events

The daemon opens the touch sensor (the `/dev/input/eventN` device on
`seat1`) and listens for finger touches. When you tap or slide your
finger, the daemon gets the coordinates and figures out which button
you touched.

### 4c: Read the config

The daemon reads `~/.config/reactive-dfr/config.toml`. This file
describes everything that appears on the Touch Bar:

- **Layers** — groups of buttons. You swipe between layers.
  - Layer 0: context buttons (change per app) + minipanel (volume,
    brightness, keyboard backlight)
  - Layer 1: F-keys (F1–F12, shown when you hold fn)
  - Layer 2: system monitor (CPU, GPU, battery, time, IP)
- **ScreensaverLayer** — what to show when the Touch Bar is idle
- **Style** — colors, fonts, sizes, corner radius

### 4d: Render at 60 FPS

The daemon runs a **60 frames-per-second render loop**. On every frame,
it draws all the buttons for the current layer using **Cairo** (a 2D
drawing library). Text, icons (SVG images), sliders, highlights — all
drawn pixel by pixel and sent to the Touch Bar display via DRM.

### 4e: Handle touches

When you tap a button, the daemon either:
- Sends a **key event** (like pressing Esc, F1, or Ctrl+C) through a
  virtual keyboard
- Runs an **OnClick command** (like opening a URL)
- Performs an **internal action** (like ExitScreensaver)

### 4f: Dim and turn off

After 30 seconds of no Touch Bar interaction, the daemon **dims** the
display to a low brightness. After 60 seconds, it turns the backlight
**off** completely. Any touch wakes it back up instantly.

### 4g: Hot-reload

The daemon watches the config file. If it changes, the daemon
immediately reloads it — no restart needed. This is how the context
daemon (next step) can change the buttons without interrupting
anything.

---

## Step 5: The Context Daemon (`touchbar-ctx`)

The `config.toml` file doesn't exist by itself — it is **generated** by
a Python program called the context daemon.

### What it does

The context daemon watches **Hyprland** (your window manager) for
window changes. Every time you switch to a different app, it:

1. Asks Hyprland: "what window is now active?"
2. Gets the window's class name (e.g., `foot`, `firefox`, `code`)
3. Looks it up in `matcher.toml` — a file that maps app names to
   "contexts" (e.g., `foot` → `terminal`, `firefox` → `browser`)
4. Loads that context's button definitions from `contexts/terminal.toml`
5. Merges them with the **base config** (`base.toml`) and the
   **minipanel** (volume/brightness/backlight sliders)
6. Writes the result to `~/.config/reactive-dfr/config.toml`
7. The reactive-dfr daemon detects the file changed and hot-reloads

**Result:** when you switch from the terminal to Firefox, the Touch
Bar buttons change from terminal shortcuts (Ctrl+C, Tab, arrows) to
browser buttons (back, forward, reload). All automatic, all instant.

### Where the config lives

```
~/.config/reactive-dfr/
├── base.toml          ← base config (layers, screensaver, minipanel, style)
├── config.toml        ← generated file (the daemon reads this one)
├── matcher.toml       ← app name → context mapping
├── contexts/          ← one .toml per app type (terminal, browser, etc.)
├── widgets/           ← scripts the buttons can run (feeder, ip, cpu, etc.)
├── state/             ← state files (screensaver_enabled, etc.)
└── feeder_config.toml ← personal feeder settings (RSS URLs, crypto IDs)
```

---

## Step 6: The Power Monitor (`touchbar-power-monitor`)

A small Python service that watches your power situation (plugged in
vs. battery) and your power profile (balanced, power-saver,
performance).

It decides whether the screensaver should be allowed to activate,
based on a simple matrix:

| Power source | Profile | Screensaver |
|---|---|---|
| Plugged in | balanced | ✅ enabled |
| Plugged in | performance | ✅ enabled |
| Battery | balanced | ✅ enabled |
| Battery | power-saver | ❌ disabled (save energy) |

When the screensaver should be enabled, it creates an empty file:

```
~/.config/reactive-dfr/state/screensaver_enabled
```

When it should be disabled, it removes the file. The reactive-dfr
daemon checks for this file every frame — if it exists, the screensaver
can activate; if not, dim/off proceeds normally.

---

## Step 7: The Screensaver

After 30 seconds of no Touch Bar interaction (with the screensaver
enabled), the daemon switches from the normal layers to the
**ScreensaverLayer**.

The screensaver layer has three buttons:

```
[ esc ]  [   feeder widget (rotating info)   ]  [ X ]
```

### The esc button
Sends the Escape key. Always available, even in screensaver mode.

### The feeder widget
This is the interesting one. It runs a Python script
(`feeder.py`) every **5 seconds**. The script rotates through
different info modules:

1. **News** — fetches RSS headlines (BBC, Hacker News) using
   `feedparser`. Caches for 10 minutes so it doesn't hammer the APIs.
2. **Crypto** — fetches crypto prices (Bitcoin, etc.) from CoinGecko.
   No API key needed.
3. **Calendar** — shows today's events using `khal`.
4. **Mail** — a placeholder reminder (not yet implemented).

Each tick, the feeder shows one item as text on the Touch Bar. Five
seconds later, it shows the next item. It cycles through all enabled
modules continuously.

When you **tap** the feeder widget, it runs `feeder_click.sh`, which:
- Reads the action associated with the current item (usually a URL)
- Opens it in your default browser using `setsid` + `xdg-open`
- The `setsid` trick is needed because the daemon runs in a sandbox
  (it can't open browsers directly), so the script escapes the sandbox
  and runs the browser as a detached process in your user session

### The X button
Sends an internal `ExitScreensaver` action. The daemon switches back to
the normal layers. You can also exit by pressing the **fn** key.

---

## The Full Boot Sequence (Timeline)

Here is what happens from the moment you press the power button to the
moment you see the Touch Bar alive:

```
0s    You press power
      Linux kernel loads

2s    USB system starts
      T1 detected in config 1 (keyboard mode)

3s    ibridge-config-switch.service runs
      T1 switches to config 2
      Touch Bar display + touch sensor appear as USB devices

4s    appletbdrm driver loads
      Touch Bar display becomes /dev/dri/card0
      udev rules assign touch sensor to seat1

5s    reactive-dfr.service starts
      Daemon opens /dev/dri/card0 as root (DRM master)
      Daemon waits for you to log in

8s    You log in (SDDM → Hyprland starts)
      reactive-dfr detects your login, drops to your user
      Loads ~/.config/reactive-dfr/config.toml
      Starts rendering buttons on the Touch Bar

9s    touchbar-ctx.service starts (your user session)
      Connects to Hyprland's event socket
      Detects your active window → generates config.toml
      Touch Bar shows buttons for your current app

9s    touchbar-power-monitor.service starts
      Checks AC/battery + power profile
      Creates screensaver_enabled state file (if appropriate)

...   You use the computer, switch apps
      Touch Bar buttons change automatically per app

+30s  You stop touching the Touch Bar
      Screensaver activates
      Feeder starts rotating: news → crypto → calendar → news → ...

      You tap the feeder → browser opens the article
      You tap X → back to normal buttons
```

---

## The Cast (Who Does What)

| Component | Language | Role |
|---|---|---|
| `appletbdrm` | C (kernel module) | Makes the Touch Bar appear as a display |
| `ibridge_switcher` | C | Flips the T1 from keyboard to display+touch mode |
| `ibridge-config-switch.service` | systemd | Runs the switcher at boot |
| `99-touchbar-seat.rules` | udev rule | Keeps Hyprland away from the Touch Bar |
| `reactive-dfr` | Rust | Draws everything, handles touch, dim/off, screensaver |
| `touchbar-ctx` | Python | Changes buttons per active app |
| `touchbar-power-monitor` | Python | Enables/disables screensaver based on power |
| `feeder.py` | Python | Rotates news/crypto/calendar on the screensaver |
| `feeder_click.sh` | Shell | Opens URLs from the feeder in your browser |
| `base.toml` | TOML | Base config: layers, style, minipanel, screensaver |
| `contexts/*.toml` | TOML | Per-app button definitions |
| `matcher.toml` | TOML | App name → context mapping |
| `config.toml` | TOML | Generated file the daemon actually reads |

---

## Where Everything Lives

| What | Where |
|---|---|
| Kernel driver source | `~/Projects/appletbdrm-t1/src/appletbdrm/` |
| Driver (installed) | `/usr/src/appletbdrm-1.2/` (DKMS) |
| Daemon source | `~/Projects/reactive-dfr/daemon/` |
| Daemon binary (installed) | `/usr/bin/reactive-dfr` |
| Context daemon source | `~/Projects/reactive-dfr/context-daemon/` |
| Deployed config | `~/.config/reactive-dfr/` |
| Feeder cache | `/var/cache/reactive-dfr/` |
| System services | `/etc/systemd/system/` |
| User services | `~/.config/systemd/user/` |
| Udev rule (live) | `/etc/udev/rules.d/99-touchbar-seat.rules` |
| Research archive | `~/Projects/touchbar-research/` |