"""Live clock for the 20x20 curtain: page 1 analog hands, page 2 digital. Left/right switches page."""

from __future__ import annotations

import math
from datetime import datetime

from . import protocol as P
from .pong import GLYPHS

W, H = P.WIDTH, P.HEIGHT
CX = CY = 10.0              # the face centre sits on the corner between four pixels
HOUR_LEN, MIN_LEN, SEC_LEN, TICK_R = 4.0, 6.5, 8.0, 9.2
HOUR_COLOR, MIN_COLOR, SEC_COLOR = 0, 30, 90        # red, yellow, cyan
QUARTER_COLOR, TICK_COLOR = 255, 120                # white, blue
BAR_COLOR, DOT_TODAY, DOT_OTHER = 90, 30, 120


def _px(x: float, y: float) -> tuple[int, int]:
    return math.floor(round(x, 6)), math.floor(round(y, 6))


def _polar(angle_deg: float, r: float) -> tuple[int, int]:
    a = math.radians(angle_deg)
    return _px(CX + r * math.sin(a), CY - r * math.cos(a))


def _hand(f: list[int], angle_deg: float, length: float, color: int) -> None:
    for i in range(int(length * 4) + 1):               # sample every quarter pixel
        x, y = _polar(angle_deg, i / 4)
        if 0 <= x < W and 0 <= y < H:
            f[y * W + x] = color


def hand_angles(now: datetime) -> tuple[float, float, float]:
    sec = now.second + now.microsecond / 1e6
    minute = now.minute + sec / 60
    hour = now.hour % 12 + minute / 60
    return hour * 30, minute * 6, now.second * 6        # second hand ticks once per second


def render_analog(now: datetime) -> list[int]:
    f = [P.PIXEL_OFF] * (W * H)
    for i in range(12):
        x, y = _polar(i * 30, TICK_R)
        f[y * W + x] = QUARTER_COLOR if i % 3 == 0 else TICK_COLOR
    hour, minute, second = hand_angles(now)
    _hand(f, second, SEC_LEN, SEC_COLOR)                # drawn first, so the others stay visible
    _hand(f, minute, MIN_LEN, MIN_COLOR)
    _hand(f, hour, HOUR_LEN, HOUR_COLOR)
    return f


def time_color(hour: int) -> int:
    if 6 <= hour < 12:
        return 30       # morning: yellow
    if 12 <= hour < 18:
        return 60       # afternoon: green
    if 18 <= hour < 22:
        return 15       # evening: orange
    return 120          # night: blue


def render_digital(now: datetime) -> list[int]:
    f = [P.PIXEL_OFF] * (W * H)
    color = time_color(now.hour)
    text = f"{now.hour:02d}:{now.minute:02d}"
    width = sum(len(GLYPHS[c][0]) for c in text) + len(text) - 1      # 17 pixels
    x, y = (W - width) // 2, 7
    for ch in text:
        glyph = GLYPHS[ch]
        if ch == ":" and now.second % 2:                # blinking colon
            x += len(glyph[0]) + 1
            continue
        for dy, row in enumerate(glyph):
            for dx, bit in enumerate(row):
                if bit == "1":
                    f[(y + dy) * W + x + dx] = 255 if ch == ":" else color
        x += len(glyph[0]) + 1
    for d in range(7):                                  # weekday dots, Monday first
        f[3 * W + 3 + 2 * d] = DOT_TODAY if d == now.weekday() else DOT_OTHER
    for i in range(round((now.second + 1) * W / 60)):   # seconds bar
        f[17 * W + i] = BAR_COLOR
    return f


class Clock:
    tick = 1.0
    hint = "left/right switch page (analog / digital) · q menu"

    def __init__(self, now=datetime.now):
        self.now = now
        self.page = 0

    def reset(self) -> None:
        self.page = 0

    def step(self) -> None:
        pass

    def key(self, name: str) -> None:
        if name in ("left", "right", "up", "down", "enter"):
            self.page = 1 - self.page

    def status(self) -> str:
        return f"{self.now():%a %d.%m.%Y %H:%M:%S}  page {self.page + 1}/2 ({'analog' if self.page == 0 else 'digital'})"

    def frame(self) -> list[int]:
        now = self.now()
        return render_analog(now) if self.page == 0 else render_digital(now)
