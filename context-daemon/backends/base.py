"""base — abstract base class for compositor backends."""

from abc import ABC, abstractmethod
from pathlib import Path
from typing import Optional, Tuple


class CompositorBackend(ABC):
    """Abstract base for a compositor backend.

    A backend knows how to query the active window's class and title
    from a specific Wayland compositor (or X11 window manager).
    """

    @abstractmethod
    def is_available(self) -> bool:
        """Return True if this compositor is currently running."""
        ...

    @abstractmethod
    def get_active_window(self) -> Tuple[str, str]:
        """Return (window_class, window_title) of the focused window.

        Returns ("", "") if no window is focused or on error.
        """
        ...

    @property
    @abstractmethod
    def name(self) -> str:
        """Human-readable name of this backend (e.g. 'Hyprland')."""
        ...

    def find_socket_dir(self) -> Optional[Path]:
        """Return the runtime socket directory for this compositor, or None."""
        return None