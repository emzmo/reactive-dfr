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

### Arch Linux (PKGBUILD) - Coming Soon
We are working on an AUR package. Once available, you will be able to install it simply with:
```bash
paru -S reactive-dfr
```

### Install Script - Coming Soon
An install.sh script will be provided to automate the build and setup process.

### Manual Build (Current)
For now, you can build it manually:

1. Clone the repository.
2. Build the Rust daemon: `cd daemon && cargo build --release`
3. Install the Python context-daemon dependencies.
4. Configure the systemd services and udev rules (see `daemon/etc/`).
5. Note: You will also need the patched kernel driver. See [appletbdrm-t1](https://github.com/emzmo/appletbdrm-t1).

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