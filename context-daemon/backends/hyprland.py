"""hyprland — Hyprland compositor backend.

Connects to .socket2.sock for events and queries hyprctl -j activewindow
for reliable class/title.
"""

import json
import os
import socket
import subprocess
from pathlib import Path
from typing import Optional, Tuple

from .base import CompositorBackend


class HyprlandBackend(CompositorBackend):
    """Hyprland backend: uses hyprctl -j activewindow + .socket2.sock events."""

    @property
    def name(self) -> str:
        return "Hyprland"

    def _instance_dir(self) -> Optional[Path]:
        env = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
        runtime = Path(os.environ.get("XDG_RUNTIME_DIR", "/run/user/1000"))
        hypr_dir = runtime / "hypr"

        if env and (hypr_dir / env).is_dir():
            return hypr_dir / env
        if hypr_dir.is_dir():
            try:
                return next(hypr_dir.glob("*/"))
            except StopIteration:
                return None
        return None

    def is_available(self) -> bool:
        return self._instance_dir() is not None

    def find_socket_dir(self) -> Optional[Path]:
        return self._instance_dir()

    def get_active_window(self) -> Tuple[str, str]:
        inst = self._instance_dir()
        if inst is None:
            return "", ""
        env = dict(os.environ, HYPRLAND_INSTANCE_SIGNATURE=inst.name)
        try:
            out = subprocess.run(
                ["hyprctl", "-j", "activewindow"],
                env=env, capture_output=True, text=True, timeout=3,
            ).stdout
            data = json.loads(out)
            return data.get("class") or "", data.get("title") or ""
        except (subprocess.SubprocessError, json.JSONDecodeError, AttributeError):
            return "", ""

    def event_socket_path(self) -> Optional[Path]:
        """Return the path to the .socket2.sock event socket."""
        inst = self._instance_dir()
        if inst is None:
            return None
        return inst / ".socket2.sock"