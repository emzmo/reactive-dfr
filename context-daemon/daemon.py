#!/usr/bin/env python3
"""daemon.py — Touch Bar contextual daemon (multi-compositor).

Watches for active window changes and swaps the tiny-dfr layout
via atomic config.toml rename (hot-reload via inotify).

Supports:
  - Hyprland (via .socket2.sock events + hyprctl -j activewindow)
  - Sway/i3  (via swaymsg -t get_tree polling)

Config:
  /etc/touchbar-daemon/config/base.toml
  /etc/touchbar-daemon/config/matcher.toml
  /etc/touchbar-daemon/config/contexts/<name>.toml

Usage:
  touchbar-daemon                # arranca el daemon
  touchbar-daemon --once         # aplica el contexto actual y sale
  touchbar-daemon --backend sway # fuerza un backend concreto
"""

import glob
import json
import logging
import os
import socket
import subprocess
import sys
import time
from pathlib import Path

CONFIG_DIR = Path(os.environ.get("TOUCHBAR_CONFIG_DIR", str(Path.home() / ".config" / "touchbar-daemon" / "config")))
BASE_PATH = CONFIG_DIR / "base.toml"
MATCHER_PATH = CONFIG_DIR / "matcher.toml"
CONTEXTS_DIR = CONFIG_DIR / "contexts"
OUT_PATH = Path(os.environ.get("TOUCHBAR_OUT", str(Path.home() / ".config" / "reactive-dfr" / "config.toml")))

from matcher import load_matcher, match_context
from composer import compose, write_atomic
from backends import detect_backend, HyprlandBackend, SwayBackend

log = logging.getLogger("touchbar-daemon")

# Polling interval for Sway/i3 (no event socket like Hyprland)
POLL_INTERVAL = 1.0  # seconds


def select_backend(force_name=None):
    """Select a backend by name, or auto-detect."""
    if force_name:
        name = force_name.lower()
        if name == "hyprland":
            return HyprlandBackend()
        if name == "sway" or name == "i3":
            return SwayBackend()
        log.error("unknown backend: %s", force_name)
        return None

    backend = detect_backend()
    if backend is None:
        log.error("no supported compositor detected (HYPRLAND_INSTANCE_SIGNATURE/SWAYSOCK/I3SOCK)")
    return backend


def apply_context(name, base_path=BASE_PATH):
    ctx_path = CONTEXTS_DIR / f"{name}.toml"
    if not ctx_path.exists():
        log.warning("context %r no existe, usando default", name)
        ctx_path = CONTEXTS_DIR / "default.toml"
        name = "default"
    text = compose(base_path, ctx_path)
    write_atomic(text, OUT_PATH)
    log.info("aplicado contexto %r -> %s", name, OUT_PATH)
    return name


def watch_hyprland(backend):
    """Watch Hyprland's .socket2.sock for activewindow events."""
    sock_path = backend.event_socket_path()
    if sock_path is None:
        log.error("no Hyprland event socket")
        return 1

    log.info("conectado a %s", sock_path)
    last = None
    while True:
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.connect(str(sock_path))
            s.settimeout(3600)
            buf = b""
            while True:
                try:
                    chunk = s.recv(4096)
                except socket.timeout:
                    chunk = b""
                if not chunk:
                    time.sleep(0.5)
                    break
                buf += chunk
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    evt = line.decode(errors="replace").strip()
                    if evt.startswith("activewindow") or evt.startswith("activedesc"):
                        cls, title = backend.get_active_window()
                        ctx = match_context(
                            load_matcher(MATCHER_PATH), cls, title
                        )
                        if ctx != last:
                            last = apply_context(ctx)
        except (OSError, ConnectionError) as e:
            log.warning("socket caido: %s; reintentando", e)
            time.sleep(2)


def watch_polling(backend):
    """Polling-based watch for compositors without event sockets (Sway/i3)."""
    log.info("polling %s every %.1fs", backend.name, POLL_INTERVAL)
    last = None
    while True:
        try:
            cls, title = backend.get_active_window()
            ctx = match_context(
                load_matcher(MATCHER_PATH), cls, title
            )
            if ctx != last:
                last = apply_context(ctx)
                log.info("window: class=%r title=%r -> context=%r", cls, title, ctx)
            time.sleep(POLL_INTERVAL)
        except Exception as e:
            log.warning("polling error: %s; reintentando", e)
            time.sleep(2)


def main():
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
    )

    # Parse simple args
    force_backend = None
    if "--once" in sys.argv:
        # Apply current context and exit
        backend = select_backend(force_backend)
        if backend is None:
            log.error("no hay compositor disponible")
            return 1
        cls, title = backend.get_active_window()
        ctx = match_context(load_matcher(MATCHER_PATH), cls, title)
        apply_context(ctx)
        log.info("(%s) contexto: %s", cls or "-", ctx)
        return 0

    # Check for --backend <name>
    for i, arg in enumerate(sys.argv):
        if arg == "--backend" and i + 1 < len(sys.argv):
            force_backend = sys.argv[i + 1]

    backend = select_backend(force_backend)
    if backend is None:
        return 1

    log.info("usando backend: %s", backend.name)

    # Use event-socket watch for Hyprland, polling for Sway/i3
    if isinstance(backend, HyprlandBackend):
        return watch_hyprland(backend)
    else:
        return watch_polling(backend)


if __name__ == "__main__":
    sys.exit(main())