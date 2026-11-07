"""Tiny JSON config (~/.config/hellofairy/config.json, override with HELLOFAIRY_CONFIG)."""

from __future__ import annotations

import json
import os
from pathlib import Path


def path() -> Path:
    return Path(os.environ.get("HELLOFAIRY_CONFIG") or Path.home() / ".config" / "hellofairy" / "config.json")


def load() -> dict:
    try:
        data = json.loads(path().read_text())
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def update(**values) -> None:
    cfg = load()
    cfg.update(values)
    p = path()
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(cfg, indent=2))
