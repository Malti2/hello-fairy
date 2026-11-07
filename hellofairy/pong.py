"""Pong vs. AI for the 20x20 curtain. You are the left paddle (green), the AI the right (red)."""

from __future__ import annotations

import random
import time

from . import protocol as P
from .snake import GLYPHS as _SNAKE_GLYPHS

W, H = P.WIDTH, P.HEIGHT
PLAYER_COLOR, AI_COLOR, BALL_COLOR = 60, 0, 30
PLAYER_X, AI_X = 1, 18
PADDLE_LEN = 4
MAX_PY = H - 1 - PADDLE_LEN  # paddle top row max so it stays inside the border

GLYPHS = dict(_SNAKE_GLYPHS)
GLYPHS.update({
    "W": ("101", "101", "111", "111", "101"),
    "I": ("111", "010", "010", "010", "111"),
    "N": ("110", "101", "101", "101", "101"),
    "L": ("100", "100", "100", "100", "111"),
    "S": ("011", "100", "010", "001", "110"),
    ":": ("0", "1", "0", "1", "0"),
    "-": ("000", "000", "111", "000", "000"),
    "B": ("110", "101", "110", "101", "110"),
    "0": ("111", "101", "101", "101", "111"),
    "1": ("010", "110", "010", "010", "111"),
    "2": ("110", "001", "010", "100", "111"),
    "3": ("110", "001", "010", "001", "110"),
    "4": ("101", "101", "111", "001", "001"),
    "5": ("111", "100", "110", "001", "110"),
    "6": ("011", "100", "110", "101", "010"),
    "7": ("111", "001", "010", "010", "010"),
    "8": ("010", "101", "010", "101", "010"),
    "9": ("010", "101", "011", "001", "110"),
})

DIFFICULTY = {"easy": 0.45, "normal": 0.72, "hard": 0.9}


def blank_with_border() -> list[int]:
    f = [P.PIXEL_OFF] * (W * H)
    for i in range(W):
        f[i] = f[(H - 1) * W + i] = f[i * W] = f[i * W + W - 1] = P.PIXEL_WHITE
    return f


def text_frame(text: str, color: int) -> list[int]:
    f = blank_with_border()
    width = sum(len(GLYPHS[c][0]) for c in text) + len(text) - 1
    x = (W - width) // 2
    y = (H - 5) // 2
    for ch in text:
        g = GLYPHS[ch]
        for dy, row in enumerate(g):
            for dx, bit in enumerate(row):
                if bit == "1":
                    f[(y + dy) * W + x + dx] = color
        x += len(g[0]) + 1
    return f


class Pong:
    def __init__(self, points=5, difficulty="normal", tick=0.14, rng=None, clock=time.monotonic):
        self.points = points
        self.skill = DIFFICULTY[difficulty] if isinstance(difficulty, str) else float(difficulty)
        self.base_tick = tick
        self.rng = rng or random.Random()
        self.clock = clock
        self.reset()

    # -- state -----------------------------------------------------------------
    def reset(self) -> None:
        self.score = [0, 0]  # player, ai
        self.over = False
        self.banners: list[tuple[list[int], float]] = []
        self._banner_start: float | None = None
        self.serve(self.rng.choice((-1, 1)))

    def serve(self, direction: int) -> None:
        self.py = self.ay = (H - PADDLE_LEN) // 2
        self.bx, self.by = W // 2, self.rng.randint(5, 14)
        self.vx, self.vy = direction, self.rng.choice((-1, 0, 1))
        self.rally = 0
        self.aim = 0

    @property
    def tick(self) -> float:
        return max(0.06, self.base_tick - 0.006 * self.rally)

    def status(self) -> str:
        return f"you {self.score[0]} : {self.score[1]} ai   (first to {self.points})"

    # -- banners (score flash / result), driven by the clock ----------------------
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

    # -- input -----------------------------------------------------------------
    def key(self, name: str) -> None:
        if name == "up":
            self.py = max(1, self.py - 1)
        elif name == "down":
            self.py = min(MAX_PY, self.py + 1)

    # -- AI --------------------------------------------------------------------
    def _predict_y(self) -> int:
        x, y, vy = self.bx, self.by, self.vy
        while x < AI_X - 1:
            x += 1
            y += vy
            if y < 1 or y > H - 2:
                vy = -vy
                y += 2 * vy
        return y

    def _ai_move(self) -> None:
        if self.vx > 0 and self.bx >= 6:
            target = self._predict_y() + self.aim
        else:
            target = (H - 1) // 2  # drift back to centre
        want = max(1, min(MAX_PY, round(target - (PADDLE_LEN - 1) / 2)))
        if want != self.ay and self.rng.random() < self.skill:
            self.ay += 1 if want > self.ay else -1

    # -- physics ---------------------------------------------------------------
    def step(self) -> None:
        if self.over or self._banner() is not None:
            return
        self._ai_move()
        nx, ny = self.bx + self.vx, self.by + self.vy
        if ny < 1 or ny > H - 2:
            self.vy = -self.vy
            ny = self.by + self.vy
        for x_pad, top, is_player in ((PLAYER_X, self.py, True), (AI_X, self.ay, False)):
            if nx == x_pad and top <= ny < top + PADDLE_LEN and (self.vx < 0) == is_player:
                off = ny - top
                if off == 0:
                    self.vy = -1
                elif off == PADDLE_LEN - 1:
                    self.vy = 1
                elif self.vy == 0:
                    self.vy = self.rng.choice((-1, 1)) if self.rng.random() < 0.3 else 0
                self.vx = -self.vx
                self.rally += 1
                if is_player:
                    self.aim = self.rng.choice((-1, 0, 0, 1, 2))
                self.by = ny
                return  # bounce: ball keeps its column this tick
        self.bx, self.by = nx, ny
        if nx <= 0:
            self._point(1)
        elif nx >= W - 1:
            self._point(0)

    def _point(self, scorer: int) -> None:
        self.score[scorer] += 1
        if self.score[scorer] >= self.points:
            self.over = True
            win = scorer == 0
            self.banners = [(text_frame(f"{self.score[0]}:{self.score[1]}", BALL_COLOR), 1.2),
                            (text_frame("WIN" if win else "LOSE", PLAYER_COLOR if win else AI_COLOR),
                             float("inf"))]
        else:
            self.banners = [(text_frame(f"{self.score[0]}:{self.score[1]}", BALL_COLOR), 1.0)]
            # serve towards the side that just lost the point
            self.serve(1 if scorer == 0 else -1)
        self._banner_start = None

    # -- rendering ---------------------------------------------------------------
    def frame(self) -> list[int]:
        b = self._banner()
        if b is not None:
            return b
        f = blank_with_border()
        for i in range(PADDLE_LEN):
            f[(self.py + i) * W + PLAYER_X] = PLAYER_COLOR
            f[(self.ay + i) * W + AI_X] = AI_COLOR
        if 1 <= self.bx <= W - 2:
            if f[self.by * W + self.bx] == P.PIXEL_OFF:
                f[self.by * W + self.bx] = BALL_COLOR
        return f
