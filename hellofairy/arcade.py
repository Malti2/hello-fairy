"""Generic real-time runner: keyboard in, terminal preview + delta updates to the curtain.

A game object provides: frame() -> 400 color bytes, step(), key(name), reset(),
tick (seconds between steps), status() -> str.
"""

from __future__ import annotations

import asyncio
import os
import re
import sys
import termios
import tty

from . import protocol as P
from .effects import ensure_draw_mode, send_changes
from .snake import ascii_view

KEYS = {"w": "up", "s": "down", "a": "left", "d": "right", "k": "down", "i": "up",
        "\x1b[A": "up", "\x1b[B": "down", "\x1b[D": "left", "\x1b[C": "right",
        "\r": "enter", "\n": "enter", "x": "rotate", "z": "rotate_ccw"}
TOKEN = re.compile(r"\x1b\[[A-D]|.", re.S)


async def run(fairy, game, *, min_interval: float = 0.06) -> str:
    """Run until q/Ctrl-C ('quit') or until game.done is set ('done')."""
    loop = asyncio.get_running_loop()
    stop = asyncio.Event()
    quit_pressed = False
    paused = False
    device: dict[int, int] = {}
    error: list[BaseException] = []

    if fairy:
        device = await ensure_draw_mode(fairy)   # shared screen state: no black flash between apps

    def on_key() -> None:
        nonlocal paused, quit_pressed
        data = os.read(sys.stdin.fileno(), 32).decode(errors="ignore")
        for tok in TOKEN.findall(data):
            if tok in KEYS:
                game.key(KEYS[tok])
            elif tok.lower() == "q" or tok == "\x03":
                quit_pressed = True
                stop.set()
            elif tok == " " and getattr(game, "space_key", False):
                game.key("space")
            elif tok == " " or tok.lower() == "p":
                paused = not paused
            elif tok.lower() == "r":
                game.reset()

    async def writer() -> None:
        nonlocal device
        try:
            while not stop.is_set():
                device = await ensure_draw_mode(fairy)   # re-initialises the curtain after a reconnect
                await send_changes(fairy, device, game.frame())
                await asyncio.sleep(min_interval)
        except Exception as err:  # lost connection etc.
            error.append(err)
            stop.set()

    last_drawn = None

    def draw() -> None:
        nonlocal last_drawn
        frame = game.frame()
        view = game.terminal_view() if hasattr(game, "terminal_view") else None
        text = f"{game.status()}  {'PAUSED' if paused else ''}"
        if fairy and fairy.reconnects:
            text += f"  (reconnected {fairy.reconnects}x)"
        if (frame, text, view) == last_drawn:
            return
        last_drawn = (frame, text, view)
        sys.stdout.write("\x1b[H" + (view if view is not None else ascii_view(None, frame)) + f"\x1b[0m\n{text:<60}\r\n"
                         f"{getattr(game, 'hint', 'w/s or up/down move · space pause · r restart · q back/quit')}\r\n\x1b[J")
        sys.stdout.flush()

    if hasattr(game, "start"):
        await game.start()

    fd = sys.stdin.fileno()
    old = termios.tcgetattr(fd)
    tty.setcbreak(fd)
    sys.stdout.write("\x1b[2J\x1b[?25l")
    loop.add_reader(fd, on_key)
    wtask = asyncio.create_task(writer()) if fairy else None
    try:
        next_tick = loop.time()
        while not stop.is_set():
            now = loop.time()
            if now >= next_tick:
                if not paused:
                    game.step()
                next_tick = now + game.tick
            draw()
            if getattr(game, "done", False):
                stop.set()
            await asyncio.sleep(0.01)
    finally:
        loop.remove_reader(fd)
        if hasattr(game, "stop"):
            await game.stop()
        if wtask:
            wtask.cancel()
        termios.tcsetattr(fd, termios.TCSADRAIN, old)
        sys.stdout.write("\x1b[?25h\x1b[0m\n")
    if error:
        raise error[0]
    return "quit" if quit_pressed else "done"
