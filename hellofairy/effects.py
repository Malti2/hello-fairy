"""Display effects. `tv_off_frames`: old CRT turn-off, outside -> centre, then dark."""

from __future__ import annotations

import asyncio
import sys

from . import protocol as P

W, H = P.WIDTH, P.HEIGHT
OFF = P.PIXEL_OFF
LINE_COLOR = 255
BAND_HEIGHTS = (18, 15, 12, 9, 7, 5, 3, 2)      # picture squashed towards the centre rows
LINE_WIDTHS = (20, 16, 12, 8, 6, 4, 2)          # bright line shrinking towards the centre columns
DOT_FADE = (255, 120, OFF)                      # final dot: white, blue afterglow, gone
FRAME_DELAY = 0.06


def _squash(frame: list[int], band: int) -> list[int]:
    top = (H - band) // 2
    out = [OFF] * (W * H)
    for y in range(band):
        src = min(H - 1, int((y + 0.5) * H / band))      # nearest source row
        out[(top + y) * W:(top + y + 1) * W] = frame[src * W:(src + 1) * W]
    return out


def tv_off_frames(frame: list[int]) -> list[tuple[list[int], float]]:
    seq = [(list(frame), FRAME_DELAY)]
    for band in BAND_HEIGHTS:                            # 1) picture collapses vertically
        seq.append((_squash(frame, band), FRAME_DELAY))
    rows = ((H - 2) // 2, (H - 2) // 2 + 1)              # the two centre rows
    for width in LINE_WIDTHS:                            # 2) line collapses horizontally
        f = [OFF] * (W * H)
        for y in rows:
            for x in range((W - width) // 2, (W - width) // 2 + width):
                f[y * W + x] = LINE_COLOR
        seq.append((f, FRAME_DELAY))
    for color in DOT_FADE:                               # 3) dot fades out
        f = [OFF] * (W * H)
        if color != OFF:
            for y in rows:
                for x in (W // 2 - 1, W // 2):
                    f[y * W + x] = color
        seq.append((f, 0.12))
    return seq


WINDOW_CLOSE = (20, 16, 12, 8, 6, 4, 2)         # window shrinking to the centre ...
WINDOW_OPEN = (4, 6, 8, 12, 16, 20)             # ... and the next picture growing out of it
WINDOW_DELAY = 0.04


def frame_from_state(state: dict) -> list[int]:
    """Row-major frame from the curtain's {device_index: colour} state."""
    return [state[P.pixel_index(x, y)] for y in range(H) for x in range(W)]


def tv_on_frames(frame: list[int]) -> list[tuple[list[int], float]]:
    """Turn-on = the turn-off animation played backwards: dot, line, picture unfolds."""
    return list(reversed(tv_off_frames(frame)))


def _box(frame: list[int], size: int) -> list[int]:
    """The picture seen through a centred square window with a white frame."""
    lo = (W - size) // 2
    hi = lo + size
    out = [OFF] * (W * H)
    for y in range(lo, hi):
        for x in range(lo, hi):
            edge = size < W and (y in (lo, hi - 1) or x in (lo, hi - 1))
            out[y * W + x] = LINE_COLOR if edge else frame[y * W + x]
    return out


def transition_frames(old: list[int], new: list[int]) -> list[tuple[list[int], float]]:
    """Close the old picture towards the centre, then open the new one from the centre."""
    seq = [(_box(old, size), WINDOW_DELAY) for size in WINDOW_CLOSE]
    seq += [(_box(new, size), WINDOW_DELAY) for size in WINDOW_OPEN]
    return seq


async def ensure_draw_mode(fairy) -> dict:
    """Put the curtain into draw mode once per connection; returns the shared screen state."""
    state = getattr(fairy, "screen_state", None)
    if state is not None:
        return state
    await fairy.require_curtain(False)
    await fairy.power(True)
    for pkt in (P.d0_packet(0x03), P.d0_packet(0x00)):
        await fairy.write(pkt)
        await asyncio.sleep(0.25)
    fairy.screen_state = {i: OFF for i in range(P.PIXEL_COUNT)}
    return fairy.screen_state


async def send_changes(fairy, state: dict, frame: list[int]) -> bool:
    """Send only changed pixels; the state is updated per packet so a cancel can't desync it."""
    want = P.frame_to_index_map(frame)
    items = sorted((i, c) for i, c in want.items() if state[i] != c)
    generation = getattr(fairy, "reconnects", 0)
    for k in range(0, len(items), P.MAX_PIXELS_PER_PACKET):
        batch = dict(items[k : k + P.MAX_PIXELS_PER_PACKET])
        for pkt in P.delta_packets(batch):
            await fairy.write(pkt)
        if getattr(fairy, "reconnects", 0) != generation:
            return False         # the link was re-created: this state is stale, caller re-inits
        state.update(batch)
    return bool(items)


async def play_frames(fairy, frames, state: dict | None = None) -> None:
    """Show frames on the curtain (delta updates) or, without a curtain, in the terminal."""
    if fairy is None:
        from .snake import ascii_view
        for frame, delay in frames:
            sys.stdout.write("\x1b[H" + ascii_view(None, frame) + "\x1b[0m\n")
            sys.stdout.flush()
            await asyncio.sleep(delay)
        return
    if state is None:
        state = await ensure_draw_mode(fairy)
    for frame, delay in frames:
        await send_changes(fairy, state, frame)
        await asyncio.sleep(delay)


def _current(fairy, fallback: list[int]) -> list[int]:
    state = getattr(fairy, "screen_state", None)
    return frame_from_state(state) if state else fallback


async def tv_on(fairy, frame: list[int]) -> None:
    await play_frames(fairy, tv_on_frames(frame))


async def tv_off(fairy, frame: list[int]) -> None:
    """Animate whatever is on the curtain right now (falls back to `frame` in the terminal)."""
    await play_frames(fairy, tv_off_frames(_current(fairy, frame)))


async def transition(fairy, old: list[int], new: list[int]) -> None:
    """Window close/open between two pictures; `old` is replaced by the real screen if known."""
    await play_frames(fairy, transition_frames(_current(fairy, old), new))
