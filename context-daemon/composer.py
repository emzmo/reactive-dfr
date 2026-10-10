#!/usr/bin/env python3
"""composer.py — generates reactive-dfr config.toml.

Merges config/base.toml (global fields + Style + fixed layers) with
the active context's layer (config/contexts/<name>.toml), then
serializes to TOML using tomli_w and writes atomically (rename) to
~/.config/reactive-dfr/config.toml, triggering reactive-dfr's
inotify live-reload.

The context provides a single [[layer]] (array of buttons) that replaces
layer 0 in the Layers array.  Layers 1+ come from base.toml and are fixed
(media keys, system monitor, etc.).
"""

import os
import tempfile
import tomllib
import tomli_w
from pathlib import Path

DEFAULT_OUT = str(Path.home() / ".config" / "reactive-dfr" / "config.toml")


def _load_toml(path):
    with open(path, "rb") as f:
        return tomllib.load(f)


def compose(base_path, context_path):
    """Return the final config.toml as a string.

    base_path: path to base.toml (global fields, Style, fixed layers)
    context_path: path to the active context .toml (provides layer 0)
    """
    base = _load_toml(base_path)
    ctx = _load_toml(context_path)

    # Context must provide a [[layer]] array.  If it uses the old
    # PrimaryLayerKeys format (no "layer" key), fall back to default
    # so the Touch Bar never shows an empty first layer.
    ctx_layer = ctx.get("layer")
    if not ctx_layer:
        default_path = Path(context_path).parent / "default.toml"
        if default_path.exists():
            ctx = _load_toml(default_path)
            ctx_layer = ctx.get("layer", [])
        else:
            ctx_layer = []

    # Start from base as the output dict
    out = {}

    # Copy all top-level scalar keys (LayerSwipe, AdaptiveBrightness, etc.)
    for key, val in base.items():
        if key == "Layers":
            continue
        if key == "Style":
            continue
        out[key] = val

    # Build Layers: context layer 0 + base layers 1+
    base_layers = base.get("Layers", [])
    out["Layers"] = [ctx_layer] + base_layers

    # Copy Style table
    if "Style" in base:
        out["Style"] = base["Style"]

    return tomli_w.dumps(out)


def write_atomic(text, out_path=None):
    """Write with atomic rename (temp in the same dir).

    reactive-dfr runs as the logged-in user and watches this
    file via inotify (IN_MOVED_TO triggers live-reload).
    """
    if out_path is None:
        out_path = DEFAULT_OUT
    out_path = Path(out_path)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=out_path.parent, prefix=".config.toml.")
    try:
        with os.fdopen(fd, "w") as f:
            f.write(text)
        os.chmod(tmp, 0o644)
        os.replace(tmp, out_path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


if __name__ == "__main__":
    import sys

    base = sys.argv[1] if len(sys.argv) > 1 else "config/base.toml"
    ctx = sys.argv[2] if len(sys.argv) > 2 else "config/contexts/default.toml"
    text = compose(base, ctx)
    print(text)