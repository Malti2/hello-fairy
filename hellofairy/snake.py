"""Real-time snake for the 20x20 Hello Fairy curtain, controlled from the Mac keyboard."""

from __future__ import annotations

import asyncio
import os
import random
import sys
import termios
import time
import tty
from collections import deque

from . import protocol as P

HEAD, BODY, FOOD, DEAD, OFF = 30, 60, 0, 0, P.PIXEL_OFF
DIRS = {"up": (0, -1), "down": (0, 1), "left": (-1, 0), "right": (1, 0)}
OPPOSITE = {"up": "down", "down": "up", "left": "right", "right": "left"}


class Game:
    def __init__(self, w=P.WIDTH - 2, h=P.HEIGHT - 2, wrap=False, rng=None, border=True):
        # Playfield is the inner 18x18; the outer ring is a white wall.
        self.w, self.h, self.wrap, self.border = w, h, wrap, border
        self.rng = rng or random.Random()
        self.reset()

    def reset(self):
        cx, cy = self.w // 2, self.h // 2
        self.snake = deque([(cx - i, cy) for i in range(3)])  # head first
        self.dir = "right"
        self.queue: deque[str] = deque()
        self.alive = True
        self.score = 0
        self.food = self._place_food()

    def _place_food(self):
        free = [(x, y) for x in range(self.w) for y in range(self.h) if (x, y) not in self.snake]
        return self.rng.choice(free) if free else None

    def turn(self, d: str):
        last = self.queue[-1] if self.queue else self.dir
        if d != last and d != OPPOSITE[last] and len(self.queue) < 2:
            self.queue.append(d)

    def step(self):
        if not self.alive:
            return
        if self.queue:
            self.dir = self.queue.popleft()
        dx, dy = DIRS[self.dir]
        hx, hy = self.snake[0]
        nx, ny = hx + dx, hy + dy
        if self.wrap:
            nx, ny = nx % self.w, ny % self.h
        elif not (0 <= nx < self.w and 0 <= ny < self.h):
            self.alive = False
            return
        eating = (nx, ny) == self.food
        body = list(self.snake) if eating else list(self.snake)[:-1]
        if (nx, ny) in body:
            self.alive = False
            return
        self.snake.appendleft((nx, ny))
        if eating:
            self.score += 1
            self.food = self._place_food()
            if self.food is None:  # board full: you won
                self.alive = False
        else:
            self.snake.pop()

    def frame(self) -> list[int]:
        W, H = P.WIDTH, P.HEIGHT
        o = (W - self.w) // 2 if self.border else 0
        f = [OFF] * (W * H)
        if self.border:
            for i in range(W):
                f[i] = f[(H - 1) * W + i] = f[i * W] = f[i * W + W - 1] = P.PIXEL_WHITE
        if self.food:
            f[(self.food[1] + o) * W + self.food[0] + o] = FOOD
        for i, (x, y) in enumerate(self.snake):
            f[(y + o) * W + x + o] = DEAD if not self.alive else (HEAD if i == 0 else BODY)
        return f


# 3x5 glyphs for the stacked "GAME / OVER" text
GLYPHS = {
    "G": ("011", "100", "101", "101", "011"),
    "A": ("010", "101", "111", "101", "101"),
    "M": ("101", "111", "111", "101", "101"),
    "E": ("111", "100", "110", "100", "111"),
    "O": ("010", "101", "101", "101", "010"),
    "V": ("101", "101", "101", "101", "010"),
    "R": ("110", "101", "110", "101", "101"),
}


def text_frame(lines=("GAME", "OVER"), color=DEAD) -> list[int]:
    """White border + stacked text, centered on the 20x20 curtain."""
    W, H = P.WIDTH, P.HEIGHT
    f = [P.PIXEL_OFF] * (W * H)
    for i in range(W):
        f[i] = f[(H - 1) * W + i] = f[i * W] = f[i * W + W - 1] = P.PIXEL_WHITE
    total_h = len(lines) * 5 + (len(lines) - 1)
    y0 = (H - total_h) // 2
    for n, line in enumerate(lines):
        x0 = (W - (len(line) * 4 - 1)) // 2
        for k, ch in enumerate(line):
            for dy, row in enumerate(GLYPHS[ch]):
                for dx, bit in enumerate(row):
                    if bit == "1":
                        f[(y0 + n * 6 + dy) * W + x0 + k * 4 + dx] = color
    return f


def game_over_frames(game: Game) -> list[tuple[list[int], float]]:
    """Game-over animation as (frame, seconds): flash, red wipe down, wipe out, final."""
    dead = game.frame()
    W, H = P.WIDTH, P.HEIGHT
    base = [P.PIXEL_OFF] * (W * H)  # border + food only, no snake
    live = [c if c in (P.PIXEL_WHITE,) else P.PIXEL_OFF for c in dead]
    seq: list[tuple[list[int], float]] = []
    for _ in range(3):
        seq += [(dead, 0.22), (live, 0.18)]
    inner = range(1, H - 1)
    for r in inner:  # red fills from the top
        f = list(live)
        for y in range(1, r + 1):
            for x in range(1, W - 1):
                f[y * W + x] = DEAD
        seq.append((f, 0.045))
    for r in inner:  # and wipes out from the top
        f = list(live)
        for y in range(r + 1, H - 1):
            for x in range(1, W - 1):
                f[y * W + x] = DEAD
        seq.append((f, 0.045))
    # after the red transition: "GAME" appears, then "OVER" below it, and stays
    seq.append((text_frame(("GAME",)), 0.6))
    seq.append((text_frame(), 0.0))
    return seq


def ascii_view(game: Game, frame: list[int] | None = None) -> str:
    from .protocol import hue_byte_to_rgb
    lines = []
    frame = frame or game.frame()  # game may be None if frame is given
    for y in range(P.HEIGHT):
        row = []
        for x in range(P.WIDTH):
            r, g, b = hue_byte_to_rgb(frame[y * P.WIDTH + x])
            row.append(f"\x1b[48;2;{r};{g};{b}m  " if (r, g, b) != (0, 0, 0) else "\x1b[48;2;25;25;25m  ")
        lines.append("".join(row) + "\x1b[0m")
    return "\n".join(lines)


KEYMAP = {"w": "up", "s": "down", "a": "left", "d": "right",
          "\x1b[A": "up", "\x1b[B": "down", "\x1b[D": "left", "\x1b[C": "right"}


async def play(fairy, *, tick=0.22, min_interval=0.06, wrap=False, speedup=0.004):
    """fairy=None -> terminal only. Keys: arrows/WASD, space pause, r restart, q quit."""
    game = Game(wrap=wrap)
    loop = asyncio.get_running_loop()
    stop = asyncio.Event()
    state = {"paused": False, "tick": tick, "restart": False, "override": None, "anim": None}
    device: dict[int, int] = {}

    if fairy:
        from .effects import ensure_draw_mode
        device = await ensure_draw_mode(fairy)   # shared screen state: no black flash between apps

    def on_key():
        data = os.read(sys.stdin.fileno(), 8).decode(errors="ignore")
        # multiple keys can arrive at once; also split bare ESC sequences
        i = 0
        while i < len(data):
            seq = data[i : i + 3] if data[i] == "\x1b" else data[i]
            i += len(seq) if seq in KEYMAP else 1
            if seq in KEYMAP:
                game.turn(KEYMAP[seq])
            elif seq.lower() == "q" or seq == "\x03":
                stop.set()
            elif seq == " ":
                state["paused"] = not state["paused"]
            elif seq.lower() == "r":
                state["restart"] = True

    async def writer():
        from .effects import ensure_draw_mode, send_changes
        nonlocal device
        sent = 0
        t0 = time.monotonic()
        while not stop.is_set():
            device = await ensure_draw_mode(fairy)   # re-initialises the curtain after a reconnect
            if await send_changes(fairy, device, state["override"] or game.frame()):
                sent += 1
            await asyncio.sleep(min_interval)

    def draw():
        sys.stdout.write("\x1b[H" + ascii_view(game, state["override"]) + "\x1b[0m\n"
                         f"score {game.score}   {'PAUSED' if state['paused'] else ''}"
                         f"{'GAME OVER - r = restart' if not game.alive else ''}      \r\n"
                         "arrows/WASD move · space pause · r restart · q quit\r\n")
        sys.stdout.flush()

    async def game_over():
        for frame, delay in game_over_frames(game):
            state["override"] = frame
            draw()
            await asyncio.sleep(delay)
        # the last frame (GAME OVER text) stays in `override` until restart

    def cancel_anim():
        if state["anim"]:
            state["anim"].cancel()
            state["anim"] = None
        state["override"] = None

    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    tty.setcbreak(fd)
    sys.stdout.write("\x1b[2J\x1b[?25l")
    loop.add_reader(fd, on_key)
    wtask = asyncio.create_task(writer()) if fairy else None
    try:
        next_tick = time.monotonic()
        while not stop.is_set():
            if state["restart"]:
                cancel_anim()
                game.reset(); state["restart"] = False; state["tick"] = tick
            if not game.alive and state["anim"] is None:
                state["anim"] = asyncio.create_task(game_over())
            now = time.monotonic()
            if now >= next_tick:
                if not state["paused"] and game.alive:
                    before = game.score
                    game.step()
                    if game.score > before:
                        state["tick"] = max(0.08, state["tick"] - speedup * 5)
                next_tick = now + state["tick"]
                draw()
            await asyncio.sleep(0.005)
    finally:
        loop.remove_reader(fd)
        cancel_anim()
        if wtask:
            wtask.cancel()
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
        sys.stdout.write("\x1b[?25h\x1b[0m\n")
    return game.score
