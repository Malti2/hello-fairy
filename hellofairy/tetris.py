"""Tetris for the 20x20 curtain: 10x18 field on the left, next piece + level on the right.

Keys: left/right move, up/x rotate, z rotate back, down soft drop, space hard drop, p pause.
"""

from __future__ import annotations

import random
import time

from . import protocol as P
from .pong import GLYPHS, blank_with_border
from .snake import text_frame as game_over_text

W, H = P.WIDTH, P.HEIGHT
COLS, ROWS = 10, 18
FIELD_X, FIELD_Y = 1, 1       # field's top-left on the 20x20 frame
DIVIDER_X = 11
PANEL_X = 12                  # panel is x=12..18

# (cells in the n x n box, n, color byte)
PIECES = {
    "I": ([(0, 1), (1, 1), (2, 1), (3, 1)], 4, 90),    # cyan
    "O": ([(0, 0), (1, 0), (0, 1), (1, 1)], 2, 30),    # yellow
    "T": ([(1, 0), (0, 1), (1, 1), (2, 1)], 3, 140),   # purple
    "S": ([(1, 0), (2, 0), (0, 1), (1, 1)], 3, 60),    # green
    "Z": ([(0, 0), (1, 0), (1, 1), (2, 1)], 3, 0),     # red
    "J": ([(0, 0), (0, 1), (1, 1), (2, 1)], 3, 120),   # blue
    "L": ([(2, 0), (0, 1), (1, 1), (2, 1)], 3, 15),    # orange
}
KICKS = [(0, 0), (-1, 0), (1, 0), (-2, 0), (2, 0), (0, -1)]
LINE_POINTS = {0: 0, 1: 100, 2: 300, 3: 500, 4: 800}


def rotated(kind: str, rot: int) -> list[tuple[int, int]]:
    cells, n, _ = PIECES[kind]
    for _ in range(rot % 4):
        cells = [(n - 1 - y, x) for x, y in cells]  # 90 degrees clockwise
    return cells


class Tetris:
    space_key = True  # arcade: space = hard drop, `p` pauses

    def __init__(self, rng=None, clock=time.monotonic):
        self.rng = rng or random.Random()
        self.clock = clock
        self.hint = "left/right move · up/x rotate · z back · down soft · space drop · p pause · q menu"
        self.reset()

    # -- state ---------------------------------------------------------------------
    def reset(self) -> None:
        self.board: list[list[int | None]] = [[None] * COLS for _ in range(ROWS)]
        self.bag: list[str] = []
        self.score = 0
        self.lines = 0
        self.over = False
        self.banners: list[tuple[list[int], float]] = []
        self._banner_start: float | None = None
        self.next_kind = self._draw()
        self._spawn()

    def _draw(self) -> str:
        if not self.bag:
            self.bag = list(PIECES)
            self.rng.shuffle(self.bag)
        return self.bag.pop()

    def _spawn(self) -> None:
        self.kind, self.next_kind = self.next_kind, self._draw()
        self.rot = 0
        cells, n, _ = PIECES[self.kind]
        self.x = (COLS - n) // 2
        self.y = -min(cy for _, cy in cells)
        if self._collides(self.kind, self.rot, self.x, self.y):
            self._game_over()

    @property
    def level(self) -> int:
        return self.lines // 10 + 1

    @property
    def tick(self) -> float:
        return max(0.08, 0.7 * 0.85 ** (self.level - 1))

    def status(self) -> str:
        return f"score {self.score}   lines {self.lines}   level {self.level}" + ("   GAME OVER - r" if self.over else "")

    # -- geometry ------------------------------------------------------------------
    def _cells(self, kind, rot, x, y):
        return [(x + cx, y + cy) for cx, cy in rotated(kind, rot)]

    def _collides(self, kind, rot, x, y) -> bool:
        for cx, cy in self._cells(kind, rot, x, y):
            if cx < 0 or cx >= COLS or cy >= ROWS:
                return True
            if cy >= 0 and self.board[cy][cx] is not None:
                return True
        return False

    def _try(self, rot, x, y) -> bool:
        if self._collides(self.kind, rot, x, y):
            return False
        self.rot, self.x, self.y = rot, x, y
        return True

    # -- banners ---------------------------------------------------------------------
    def _banner(self):
        while self.banners:
            frame, secs = self.banners[0]
            if self._banner_start is None:
                self._banner_start = self.clock()
            if secs == float("inf") or self.clock() - self._banner_start < secs:
                return frame
            self.banners.pop(0)
            self._banner_start = None
        return None

    def _game_over(self) -> None:
        self.over = True
        base = self._compose(active=False)
        seq = []
        for k in range(1, ROWS + 1):  # red wipes up from the bottom of the field
            f = list(base)
            for r in range(ROWS - k, ROWS):
                for c in range(COLS):
                    f[(FIELD_Y + r) * W + FIELD_X + c] = 0
            seq.append((f, 0.05))
        seq.append((game_over_text(), float("inf")))
        self.banners, self._banner_start = seq, None

    # -- input -----------------------------------------------------------------------
    def key(self, name: str) -> None:
        if self.over or self._banner() is not None:
            return
        if name == "left":
            self._try(self.rot, self.x - 1, self.y)
        elif name == "right":
            self._try(self.rot, self.x + 1, self.y)
        elif name == "down":
            if self._try(self.rot, self.x, self.y + 1):
                self.score += 1
        elif name in ("up", "rotate", "rotate_ccw"):
            new = (self.rot + (3 if name == "rotate_ccw" else 1)) % 4
            for dx, dy in KICKS:
                if self._try(new, self.x + dx, self.y + dy):
                    break
        elif name == "space":
            dist = 0
            while self._try(self.rot, self.x, self.y + 1):
                dist += 1
            self.score += 2 * dist
            self._lock()

    def step(self) -> None:
        if self.over or self._banner() is not None:
            return
        if not self._try(self.rot, self.x, self.y + 1):
            self._lock()

    def _lock(self) -> None:
        color = PIECES[self.kind][2]
        for cx, cy in self._cells(self.kind, self.rot, self.x, self.y):
            if cy < 0:
                self._game_over()
                return
            self.board[cy][cx] = color
        full = [r for r in range(ROWS) if all(v is not None for v in self.board[r])]
        for r in full:
            del self.board[r]
            self.board.insert(0, [None] * COLS)
        self.lines += len(full)
        self.score += LINE_POINTS[len(full)] * self.level
        self._spawn()

    # -- rendering ---------------------------------------------------------------------
    def _compose(self, active=True) -> list[int]:
        f = blank_with_border()
        for y in range(1, H - 1):
            f[y * W + DIVIDER_X] = P.PIXEL_WHITE
        for r in range(ROWS):
            for c in range(COLS):
                if self.board[r][c] is not None:
                    f[(FIELD_Y + r) * W + FIELD_X + c] = self.board[r][c]
        if active:
            color = PIECES[self.kind][2]
            for cx, cy in self._cells(self.kind, self.rot, self.x, self.y):
                if cy >= 0:
                    f[(FIELD_Y + cy) * W + FIELD_X + cx] = color
        # next piece, centred in the 7-wide panel
        cells = rotated(self.next_kind, 0)
        minx, maxx = min(c[0] for c in cells), max(c[0] for c in cells)
        miny = min(c[1] for c in cells)
        px = PANEL_X + (7 - (maxx - minx + 1)) // 2 - minx
        for cx, cy in cells:
            f[(2 + cy - miny) * W + px + cx] = PIECES[self.next_kind][2]
        # level digit
        glyph = GLYPHS[str(min(self.level, 9))]
        for dy, row in enumerate(glyph):
            for dx, bit in enumerate(row):
                if bit == "1":
                    f[(9 + dy) * W + 14 + dx] = 30
        return f

    def frame(self) -> list[int]:
        b = self._banner()
        return b if b is not None else self._compose()
