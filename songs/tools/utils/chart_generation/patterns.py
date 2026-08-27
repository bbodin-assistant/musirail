"""Deterministic lane-pattern grammar used by every difficulty."""

from __future__ import annotations

import hashlib


PATTERNS: dict[str, tuple[int, ...]] = {
    "alternate": (1, 3, 1, 3, 0, 4, 1, 3, 2, 3, 1, 4, 0, 3, 1, 2),
    "run": (0, 1, 2, 3, 4, 3, 2, 1, 0, 1, 2, 3, 4, 2, 1, 3),
    "mirror": (0, 4, 1, 3, 2, 3, 1, 4, 0, 4, 2, 2, 1, 3, 0, 4),
    "sweep": (0, 1, 2, 3, 4, 4, 3, 2, 1, 0, 1, 2, 3, 4, 2, 1),
    "center_out": (2, 1, 3, 0, 4, 1, 3, 2, 0, 2, 4, 3, 1, 2, 3, 1),
    "syncopated": (1, 1, 3, 2, 4, 2, 0, 3, 1, 4, 2, 0, 3, 3, 1, 2),
}


def lane_for_phrase(seed: int, phrase_id: int, phrase_slot: int) -> tuple[int, str]:
    """Return a stable lane and motif name for a repeated phrase position."""

    names = tuple(PATTERNS)
    digest = hashlib.sha256(f"{seed}:{phrase_id}".encode()).digest()
    pattern_name = names[int.from_bytes(digest[:2], "big") % len(names)]
    pattern = PATTERNS[pattern_name]
    rotation = digest[2] % len(pattern)
    mirror = bool(digest[3] & 1)
    lane = pattern[(phrase_slot + rotation) % len(pattern)]
    if mirror:
        lane = 4 - lane
    return lane, pattern_name
