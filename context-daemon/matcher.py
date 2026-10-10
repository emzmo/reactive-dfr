#!/usr/bin/env python3
"""matcher.py — asigna class/title de la ventana activa a un contexto.

Carga config/matcher.toml (reglas [[context]]) y resuelve la primera
coincidencia. `class` compara exacto (minúsculas); `title` es substring.
Sin coincidencia -> "default".
"""

import tomllib
from pathlib import Path

DEFAULT_CONTEXT = "default"


def load_matcher(path):
    with open(path, "rb") as f:
        data = tomllib.load(f)
    return data.get("context", [])


def match_context(matcher, win_class, win_title):
    win_class = (win_class or "").strip().lower()
    win_title = (win_title or "").strip().lower()

    for rule in matcher:
        name = rule.get("name")
        classes = [c.lower() for c in rule.get("class", [])]
        titles = [t.lower() for t in rule.get("title", [])]
        if win_class and win_class in classes:
            return name
        if titles and any(t and t in win_title for t in titles):
            return name
    return DEFAULT_CONTEXT
