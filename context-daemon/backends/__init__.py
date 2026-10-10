"""backends — pluggable compositor backends for the Touch Bar context daemon.

Each backend implements the CompositorBackend ABC, providing
get_active_window() -> (class, title).

Auto-detection picks the right backend based on environment variables
and running processes.
"""

from .base import CompositorBackend
from .hyprland import HyprlandBackend
from .sway import SwayBackend


def detect_backend():
    """Auto-detect the running compositor and return a backend instance.

    Returns None if no supported compositor is found.
    """
    backends = [HyprlandBackend, SwayBackend]
    for cls in backends:
        backend = cls()
        if backend.is_available():
            return backend
    return None


__all__ = ["CompositorBackend", "HyprlandBackend", "SwayBackend", "detect_backend"]