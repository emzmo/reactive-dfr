"""sway — Sway/i3 compositor backend.

Uses swaymsg -t get_tree to find the focused window's class and title.
Also supports i3 via i3-msg.
"""

import json
import os
import subprocess
from pathlib import Path
from typing import Optional, Tuple

from .base import CompositorBackend


class SwayBackend(CompositorBackend):
    """Sway/i3 backend: uses swaymsg (or i3-msg) -t get_tree for window info."""

    @property
    def name(self) -> str:
        return "Sway"

    def _is_sway(self) -> bool:
        return bool(os.environ.get("SWAYSOCK"))

    def _is_i3(self) -> bool:
        return bool(os.environ.get("I3SOCK"))

    def is_available(self) -> bool:
        return self._is_sway() or self._is_i3()

    def get_active_window(self) -> Tuple[str, str]:
        if self._is_sway():
            return self._sway_focused_window("swaymsg")
        if self._is_i3():
            return self._sway_focused_window("i3-msg")
        return "", ""

    def _sway_focused_window(self, cmd: str) -> Tuple[str, str]:
        """Query swaymsg/i3-msg -t get_tree and find the focused window.

        The tree is nested; we walk it to find the focused node with a window.
        """
        try:
            out = subprocess.run(
                [cmd, "-t", "get_tree"],
                capture_output=True, text=True, timeout=3,
            ).stdout
            tree = json.loads(out)
        except (subprocess.SubprocessError, json.JSONDecodeError):
            return "", ""

        # Find the focused workspace, then the focused window in it
        focused = self._find_focused_node(tree)
        if focused is None:
            return "", ""
        props = focused.get("window_properties", {})
        return props.get("class") or "", props.get("title") or ""

    def _find_focused_node(self, node):
        """Recursively find the focused node with a window_id in the tree."""
        if not isinstance(node, dict):
            return None

        # Check if this node is the focused window
        if node.get("focused") and node.get("type") == "con" and node.get("window"):
            return node

        # Recurse into nodes and floating_nodes
        for child_key in ("nodes", "floating_nodes"):
            for child in node.get(child_key, []):
                result = self._find_focused_node(child)
                if result is not None:
                    return result

        return None

    def event_socket_path(self) -> Optional[Path]:
        """Sway doesn't use a simple event socket like Hyprland.

        Subscribe via: swaymsg -t subscribe -m '["window"]'
        This backend uses polling instead of a persistent socket.
        """
        sock = os.environ.get("SWAYSOCK")
        if sock:
            return Path(sock)
        return None