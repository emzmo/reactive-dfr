# reactive-dfr

A reactive Touch Bar daemon for Apple T1/T2 Macs on Linux. The Touch Bar adapts to the active window automatically, providing contextual controls for whatever application you are using.

## Introduction

`reactive-dfr` is a Touch Bar daemon that brings the dynamic function row experience to Linux on Apple MacBooks. It evolved from the excellent work of the AsahiLinux team and the open-source community. 

This project combines a Rust-based render engine (forked from `not-quite-tiny-dfr` by seojoonlee-dev, which itself forked from `tiny-dfr` by AsahiLinux) with a Python-based contextual switching daemon. The result is a Touch Bar that is not just a static row of keys, but a reactive interface that changes based on what you are doing.

## How it works

The project is divided into two main components:

1. **`daemon/` (Rust)**: The render engine. It communicates directly with the kernel via DRM (Direct Rendering Manager) and libinput to draw the Touch Bar UI and handle touch events. It supports sliders, expandable widgets, custom shell-command widgets, and full theming.
   - **T1 Adaptation**: Includes specific fixes for the Apple T1 chip protocol (sync probe, 16-byte preamble drain, one-behind ACK, stale pipe clearing) to ensure stability on MacBook Pro 2016-2017 models.

2. **`context-daemon/` (Python)**: The brain. It listens to Hyprland (via socket2) or Sway (via polling) to detect the active window. When you switch apps, it composes a new TOML configuration file and saves it. The Rust daemon detects this change via `inotify` and instantly hot-reloads the new layout. Firefox gets navigation buttons, the terminal gets signal shortcuts, and so on.

## Requirements

- **Hardware**: Apple T1 or T2 MacBook (Tested on MacBookPro14,2 / 15" 2017)
- **OS**: Linux (Arch Linux based recommended)
- **Kernel**: 7.x+ with `appletbdrm` driver compiled (DKMS recommended)
- **Compositor**: Hyprland or Sway
- **Dependencies**: 
  - Rust / Cargo (to build the daemon)
  - Python 3.11+ and `tomli_w` (for the context-daemon)
  - `cairo`, `pango`, `librsvg`, `libdrm`, `libinput`, `systemd-libs`
  - `wl-clipboard` (for clipboard widget features)

## Installation

Requires [appletbdrm-t1](https://github.com/emzmo/appletbdrm-t1) to be installed first (the kernel driver).

### Option 1 — Install script (any distro)

```bash
git clone https://github.com/emzmo/reactive-dfr.git
cd reactive-dfr
sudo ./install.sh install
sudo reboot
```

The script compiles the Rust daemon, installs all system components
(binary, services, config, udev rules, SVG icons), and deploys
user config + widgets to `~/.config/reactive-dfr/`.

Other commands:

```bash
./install.sh status            # show what's installed
sudo ./install.sh uninstall    # remove system components (keeps user config)
```

### Option 2 — Manual

```bash
git clone https://github.com/emzmo/reactive-dfr.git
cd reactive-dfr

# Build the Rust daemon
cd daemon && cargo build --release && cd ..

# Install binary
sudo install -Dm755 daemon/target/release/reactive-dfr /usr/bin/reactive-dfr

# Install shared assets (SVG icons, default config, shipped widgets)
sudo mkdir -p /usr/share/reactive-dfr
sudo cp -r daemon/share/reactive-dfr/* /usr/share/reactive-dfr/

# Install context daemon (Python)
sudo mkdir -p /usr/lib/reactive-dfr/context-daemon/{backends,scripts,widgets}
sudo install -Dm755 context-daemon/daemon.py   /usr/lib/reactive-dfr/context-daemon/daemon.py
sudo install -Dm644 context-daemon/composer.py /usr/lib/reactive-dfr/context-daemon/composer.py
sudo install -Dm644 context-daemon/matcher.py  /usr/lib/reactive-dfr/context-daemon/matcher.py
sudo install -Dm644 context-daemon/backends/*.py /usr/lib/reactive-dfr/context-daemon/backends/
sudo install -Dm644 context-daemon/scripts/power_monitor.py /usr/lib/reactive-dfr/context-daemon/scripts/
sudo cp context-daemon/widgets/* /usr/lib/reactive-dfr/context-daemon/widgets/

# Install system config
sudo mkdir -p /etc/reactive-dfr/config/contexts
sudo install -Dm644 context-daemon/config/base.toml    /etc/reactive-dfr/config/base.toml
sudo install -Dm644 context-daemon/config/matcher.toml /etc/reactive-dfr/config/matcher.toml
sudo cp context-daemon/config/contexts/*.toml /etc/reactive-dfr/config/contexts/

# Install systemd services
sudo install -Dm644 daemon/etc/systemd/system/reactive-dfr.service /etc/systemd/system/
sudo install -Dm644 daemon/etc/systemd/system/systemd-backlight@backlight:appletb_backlight.service /etc/systemd/system/
sudo install -Dm644 context-daemon/systemd/touchbar-ctx.service /usr/lib/systemd/user/
sudo install -Dm644 context-daemon/systemd/touchbar-power-monitor.service /usr/lib/systemd/user/
sudo systemctl daemon-reload
sudo systemctl enable reactive-dfr.service

# Install udev rules
sudo install -Dm644 daemon/etc/udev/rules.d/99-touchbar-reactive-dfr.rules /etc/udev/rules.d/
sudo install -Dm644 daemon/etc/udev/rules.d/99-touchbar-seat.rules /etc/udev/rules.d/
sudo udevadm control --reload-rules

# Deploy user config + widgets
./reactive-dfr-setup

# Enable user services
systemctl --user enable --now touchbar-ctx.service
systemctl --user enable --now touchbar-power-monitor.service

sudo reboot
```

### Option 3 — PKGBUILD (Arch Linux, not yet published on AUR)

```bash
git clone https://github.com/emzmo/reactive-dfr.git
cd reactive-dfr
makepkg -si
reactive-dfr-setup
sudo systemctl enable reactive-dfr.service
systemctl --user enable --now touchbar-ctx.service
systemctl --user enable --now touchbar-power-monitor.service
sudo reboot
```

## Future Ideas

- **Game Profiles**: Deep integration with games. Imagine playing Age of Empires and having the Touch Bar display your resources, or when selecting a villager, showing building options.
- **D-Bus API**: Expose an API to allow any application to push custom layouts directly.
- **More Compositor Support**: Add backends for Wayfire, River, etc.
- **NixOS Module**: Provide a native NixOS module for declarative configuration.

## Credits

This project stands on the shoulders of giants.

- **AsahiLinux team** - For the original `tiny-dfr` and the reverse engineering of Apple Silicon.
- **seojoonlee-dev** - For `not-quite-tiny-dfr`, which added theming, sliders, and scrollable layers.
- **Seborider** - For documenting and implementing the T1 USB protocol dialect fixes.