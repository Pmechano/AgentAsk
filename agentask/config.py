"""Validated settings, re-read for every question; local overrides stay out of Git."""

import json
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


def load_config(path=None):
    path = Path(path or ROOT / "config.json")
    defaults = json.loads((ROOT / "config.defaults.json").read_text(encoding="utf-8"))
    try:
        overrides = json.loads(path.read_text(encoding="utf-8-sig"))
    except FileNotFoundError:
        overrides = {}
    except (ValueError, OSError) as exc:
        raise ValueError("Cannot read config %s: %s" % (path, exc)) from exc
    if not isinstance(overrides, dict):
        raise ValueError("Config must be a JSON object: %s" % path)
    for section, values in overrides.items():
        if section not in defaults or not isinstance(values, dict):
            raise ValueError("Unknown or invalid config section: %s" % section)
        for key, value in values.items():
            if key not in defaults[section]:
                raise ValueError("Unknown setting: %s.%s" % (section, key))
            defaults[section][key] = value
    for section, key in (("appearance", "edge_animation"), ("behavior", "enabled"),
                         ("behavior", "topmost"), ("behavior", "timeout_enabled")):
        if type(defaults[section][key]) is not bool:
            raise ValueError("%s.%s must be true or false" % (section, key))
    for section, key, low, high, integer in (
        ("appearance", "window_scale", 0.7, 1.5, False),
        ("appearance", "font_size", 12, 28, True),
        ("behavior", "timeout_seconds", 1, 86400, True),
    ):
        value = defaults[section][key]
        if (type(value) not in (int, float) or not math.isfinite(value)
                or not low <= value <= high or (integer and value != int(value))):
            raise ValueError("%s.%s must be %s from %s to %s" % (
                section, key, "an integer" if integer else "a number", low, high))
    return defaults
