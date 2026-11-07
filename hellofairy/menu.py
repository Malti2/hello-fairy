"""Main menu shown on the curtain (icon + position dots) and in the terminal."""

from __future__ import annotations

from . import protocol as P
from .pong import blank_with_border

W, H = P.WIDTH, P.HEIGHT
CODES = {".": P.PIXEL_OFF, "P": 140, "O": 15, "G": 60, "Y": 30, "R": 0, "B": 120, "W": P.PIXEL_WHITE, "C": 90}

ICONS = {
    "snake": [
        ".GGGGGGGGG....",
        ".G.......G....",
        ".G..R....G....",
        ".GGGGGGGGG....",
        ".........G....",
        ".YGGGGGGGG....",
    ],
    "pong": [
        ".G..........R.",
        ".G..........R.",
        ".G....Y.....R.",
        ".G..........R.",
        "..............",
        "WWWWWWWWWWWWWW",
    ],
    "tetris": [
        "....PPP.....",
        ".....P......",
        "............",
        "............",
        "............",
        "G.......YY..",
        "GG..B...YY..",
        "GRRBBB.OOO..",
        "CCCCCRRBOO..",
    ],
    "mario": [
        "...Y........",
        "............",
        "............",
        "..R.....GG..",
        "..R.....GG..",
        "......P.GG..",
        "OOOOOOOOOOOO",
        "OOOOOOOOOOOO",
    ],
    "clock": [
        "..WWWWWWW..",
        ".W...Y...W.",
        "W....Y....W",
        "W....Y....W",
        "W....RRR..W",
        "W.........W",
        ".W.......W.",
        "..WWWWWWW..",
    ],
    "weather": [
        "....Y.......",
        ".Y..Y..Y....",
        "..YYYYY.....",
        "..YYYYWWW...",
        "...YYWWWWWW.",
        "....WWWWWWW.",
        ".....WWWWW..",
    ],
    "mirror": [
        "....WWWW....",
        "..WW....WW..",
        "WW..CCCC..WW",
        "W..CCBBCC..W",
        "WW..CCCC..WW",
        "..WW....WW..",
        "....WWWW....",
    ],
    "quit": [
        "R..........R",
        ".R........R.",
        "..R......R..",
        "...R....R...",
        "....R..R....",
        ".....RR.....",
        ".....RR.....",
        "....R..R....",
        "...R....R...",
        "..R......R..",
        ".R........R.",
        "R..........R",
    ],
}

ITEMS = [("snake", "Snake"), ("pong", "Pong"), ("tetris", "Tetris"), ("mario", "Mario"), ("mirror", "Mirror"), ("clock", "Clock"), ("weather", "Weather"), ("quit", "Quit")]


class Menu:
    tick = 0.2
    hint = "up/down/left/right choose · enter start · q quit"

    def __init__(self, items=ITEMS):
        self.items = items
        self.index = 0
        self.done = False
        self.choice: str | None = None
        self.notice = ""           # e.g. why the last app could not start

    def reset(self) -> None:
        self.done, self.choice = False, None

    def step(self) -> None:
        pass

    def key(self, name: str) -> None:
        if name in ("up", "left"):
            self.index = (self.index - 1) % len(self.items)
        elif name in ("down", "right"):
            self.index = (self.index + 1) % len(self.items)
        elif name == "enter":
            self.choice = self.items[self.index][0]
            self.done = True

    def status(self) -> str:
        line = "  ".join(f"[{n}]" if i == self.index else f" {n} " for i, (_, n) in enumerate(self.items))
        return line + (f"   ! {self.notice}" if self.notice else "")

    def frame(self) -> list[int]:
        f = blank_with_border()
        icon = ICONS[self.items[self.index][0]]
        iw, ih = len(icon[0]), len(icon)
        x0, y0 = (W - iw) // 2, 2 + (12 - ih) // 2 + 1
        for dy, row in enumerate(icon):
            for dx, ch in enumerate(row):
                f[(y0 + dy) * W + x0 + dx] = CODES[ch]
        n = len(self.items)
        dots_x = (W - (2 * n - 1)) // 2
        for i in range(n):  # position indicator, selected = yellow
            f[17 * W + dots_x + 2 * i] = 30 if i == self.index else 120
        return f
