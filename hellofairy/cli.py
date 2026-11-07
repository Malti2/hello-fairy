"""`fairy` command line: one-shot commands or an interactive shell."""

from __future__ import annotations

import argparse
import asyncio
import colorsys
import shlex
import sys
import time

from . import __version__, imaging
from . import protocol as P
from .ble import Fairy, save_default, scan

NAMED_HSV = {  # hue deg
    "red": 0, "orange": 30, "yellow": 55, "green": 120, "cyan": 180,
    "blue": 240, "purple": 275, "magenta": 300, "pink": 330,
}


def parse_color(text: str) -> tuple[int, int, int]:
    """name | #rrggbb | r,g,b -> (h 0-359, s 0-100, v 0-100)."""
    t = text.strip().lower()
    if t in NAMED_HSV:
        return NAMED_HSV[t], 100, 100
    if t == "white":
        return 0, 0, 100
    if t == "warm":
        return 35, 40, 100
    if t.startswith("#") and len(t) == 7:
        rgb = tuple(int(t[i : i + 2], 16) for i in (1, 3, 5))
    elif "," in t:
        rgb = tuple(int(p) for p in t.split(","))
        if len(rgb) != 3:
            raise ValueError("use r,g,b")
    else:
        raise ValueError(f"unknown color {text!r}: name, #rrggbb or r,g,b")
    h, s, v = colorsys.rgb_to_hsv(*(c / 255 for c in rgb))
    return int(h * 360) % 360, round(s * 100), round(v * 100)


def log(msg: str) -> None:
    print(f"· {msg}", file=sys.stderr)


def progress(i: int, n: int, label: str) -> None:
    print(f"\r  [{i}/{n}] {label:<24}", end="", file=sys.stderr, flush=True)
    if i == n:
        print(file=sys.stderr)


def add_image_opts(p):
    p.add_argument("--fit", choices=["contain", "cover", "stretch"], default="contain",
                   help="how to fit non-square images (default: contain)")
    p.add_argument("--dark", type=float, default=0.18, help="brightness below this = LED off (0-1)")
    p.add_argument("--white", type=float, default=0.18, help="saturation below this = white (0-1)")
    p.add_argument("--boost", type=float, default=1.0, help="brighten source before conversion")
    p.add_argument("--dry-run", action="store_true", help="only show preview, no Bluetooth")
    p.add_argument("--save-preview", metavar="PNG", help="write the quantized 20x20 preview as PNG")
    p.add_argument("--force", action="store_true", help="skip device/MTU safety checks")


def build_parser() -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(prog="fairy", description="Control Hello Fairy BLE lights from the terminal.")
    ap.add_argument("--version", action="version", version=__version__)
    ap.add_argument("-d", "--device", help="BLE address/UUID (default: last used, else auto-scan)")
    sub = ap.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("scan", help="find Hello Fairy devices"); s.add_argument("-t", "--timeout", type=float, default=6)
    s.add_argument("--save", action="store_true", help="save the strongest device as default")
    s.add_argument("--all", action="store_true", help="list ALL nearby BLE devices (to find the lights)")
    sub.add_parser("info", help="device model/firmware/LED layout")
    sub.add_parser("status", help="current power/mode/color")
    sub.add_parser("on"); sub.add_parser("off")
    s = sub.add_parser("color", help="solid color: name, #rrggbb or r,g,b"); s.add_argument("color")
    s.add_argument("-b", "--brightness", type=int, help="override brightness 0-100")
    s = sub.add_parser("brightness"); s.add_argument("percent", type=int)
    s = sub.add_parser("preset", help="built-in effect by number 1-58 or name")
    s.add_argument("preset"); s.add_argument("-b", "--brightness", type=int, default=50)
    sub.add_parser("presets", help="list named effects")

    s = sub.add_parser("image", help="upload a picture to the 20x20 curtain"); s.add_argument("file")
    add_image_opts(s)
    s = sub.add_parser("text", help="show text on the curtain"); s.add_argument("text")
    s.add_argument("-c", "--color", default="red"); s.add_argument("--size", type=int, default=9)
    s.add_argument("--hold", type=float, default=3.0, help="seconds per page if text is >1 page")
    add_image_opts(s)
    sub.add_parser("clear", help="blank the curtain").add_argument("--force", action="store_true")
    s = sub.add_parser("move", help="movement of the uploaded picture")
    s.add_argument("movement", choices=list(P.MOVEMENTS)); s.add_argument("-s", "--speed", type=int, default=50)
    s.add_argument("-b", "--brightness", type=int, default=100)
    s = sub.add_parser("anim", help="2-picture blink/breathe animation (experimental)")
    s.add_argument("a"); s.add_argument("b", nargs="?", help="second image (omit for GIF: first+middle frame)")
    s.add_argument("--mode", choices=["blink", "breathe"], default="blink")
    s.add_argument("-s", "--speed", type=int, default=50); s.add_argument("-b", "--brightness", type=int, default=100)
    add_image_opts(s)
    s = sub.add_parser("apps", help="open the app menu (arrow keys + Enter) with all games and apps")
    s.add_argument("--min-interval", type=float, default=0.06, help="min seconds between BLE writes")
    s.add_argument("--dry-run", action="store_true", help="terminal only, no Bluetooth")
    s.add_argument("--difficulty", choices=["easy", "normal", "hard"], default="normal", help="Pong: AI strength")
    s.add_argument("--points", type=int, default=5, help="Pong: points needed to win")
    s.add_argument("--camera", type=int, default=0, help="Mirror: camera index")
    s.add_argument("--demo", action="store_true", help="Mirror: synthetic camera instead of a real one")
    s.add_argument("--budget", type=int, default=P.MAX_PIXELS_PER_PACKET, help="Mirror: max pixels sent per step")
    s.add_argument("--city", help="Weather: city name (saved for next time)")
    sub.add_parser("shell", help="interactive session (keeps the connection open)")
    return ap


def img_kw(a):
    return dict(fit=a.fit, dark=a.dark, white=a.white, boost=a.boost)


def show_preview(frame, a):
    print(imaging.preview_ansi(frame))
    if a.save_preview:
        imaging.save_preview(frame, a.save_preview)
        log(f"preview saved to {a.save_preview}")


def resolve_preset(text: str) -> int:
    t = text.lower().replace("_", "-").replace(" ", "-")
    if t.isdigit():
        return int(t)
    if t in P.PRESETS:
        return P.PRESETS[t]
    raise ValueError(f"unknown preset {text!r}; see `fairy presets`")


def fmt_status(st):
    if not st:
        return "no status reply"
    if st["mode"] == 1:
        return f"power={'on' if st['power'] else 'off'} mode=color hue={st['hue']} sat={st['saturation']:.0f}% bri={st['brightness']:.0f}%"
    if st["mode"] == 2:
        return f"power={'on' if st['power'] else 'off'} mode=preset #{st['preset']} bri={st['brightness']}"
    return f"power={'on' if st['power'] else 'off'} mode={st['mode']}"


async def run(a, fairy: Fairy) -> None:
    c = a.cmd
    if c == "info":
        print(await fairy.get_info() or "no reply")
    elif c == "status":
        print(fmt_status(await fairy.get_status()))
    elif c in ("on", "off"):
        await fairy.power(c == "on")
    elif c == "color":
        h, s, v = parse_color(a.color)
        await fairy.color(h, s, a.brightness if a.brightness is not None else v)
    elif c == "brightness":
        await fairy.brightness(a.percent)
    elif c == "preset":
        await fairy.preset(resolve_preset(a.preset), a.brightness)
    elif c == "image":
        frame = imaging.load_frame(a.file, **img_kw(a))
        show_preview(frame, a)
        await fairy.send_image(frame, force=a.force, progress=progress)
    elif c == "text":
        pages = imaging.render_text_pages(a.text, imaging.parse_pixel_color(a.color), size=a.size)
        for i, pg in enumerate(pages):
            show_preview(pg, a)
            await fairy.send_image(pg, force=a.force, progress=progress)
            if i < len(pages) - 1:
                await asyncio.sleep(a.hold)
    elif c == "clear":
        await fairy.send_image([P.PIXEL_OFF] * P.PIXEL_COUNT, force=a.force, progress=progress)
    elif c == "move":
        await fairy.playback("picture", a.movement, a.speed, a.brightness)
    elif c == "anim":
        if a.b:
            frames = [imaging.load_frame(a.a, **img_kw(a)), imaging.load_frame(a.b, **img_kw(a))]
        else:
            frames = imaging.gif_frames(a.a, 2, **img_kw(a))
        for f in frames:
            show_preview(f, a)
        await fairy.send_animation(frames, force=a.force, progress=progress)
        await fairy.playback("animation", a.mode, a.speed, a.brightness)


DRY = {"image", "text", "anim"}


def make_app(name: str, a):
    """Build an arcade-style app for the menu (everything except snake, which has its own loop)."""
    if name == "pong":
        from .pong import Pong
        return Pong(a.points, a.difficulty)
    if name == "tetris":
        from .tetris import Tetris
        return Tetris()
    if name == "mario":
        from .mario import Mario
        return Mario()
    if name == "clock":
        from .clock import Clock
        return Clock()
    if name == "weather":
        from .weather import Weather
        return Weather(a.city)
    if name == "mirror":                # optional extra: imported only when chosen
        from .mirror import Mirror
        return Mirror(budget=a.budget, camera=a.camera, demo=a.demo)
    raise ValueError(f"unknown app {name!r}")


async def apps_menu(a) -> None:
    from contextlib import AsyncExitStack

    from .arcade import run as arcade_run
    from .effects import ensure_draw_mode, transition, tv_off, tv_on
    from .menu import Menu
    from .snake import Game as SnakeGame
    from .snake import play as snake_play

    async with AsyncExitStack() as stack:
        fairy = None if a.dry_run else await stack.enter_async_context(Fairy(a.device, log=log))
        menu = Menu()
        try:
            if fairy:
                await ensure_draw_mode(fairy)
            else:
                sys.stdout.write("\x1b[2J")
            await tv_on(fairy, menu.frame())                      # start-up: TV switches on
            while True:
                menu.reset()
                if await arcade_run(fairy, menu, min_interval=a.min_interval) == "quit" or menu.choice in (None, "quit"):
                    break
                menu.notice = ""
                try:
                    if menu.choice == "snake":
                        game = SnakeGame()
                    else:
                        game = make_app(menu.choice, a)
                except Exception as err:      # e.g. missing optional package, no camera
                    menu.notice = f"{menu.choice}: {err}"
                    continue
                try:
                    await transition(fairy, menu.frame(), game.frame())   # menu closes, app opens
                    if menu.choice == "snake":
                        await snake_play(fairy, min_interval=a.min_interval)
                    else:
                        game.reset()                                      # restart timers/banners
                        await arcade_run(fairy, game, min_interval=a.min_interval)
                except (ConnectionError, KeyboardInterrupt):
                    raise
                except Exception as err:      # e.g. camera lost: back to the menu with a note
                    menu.notice = f"{menu.choice}: {err}"
                finally:
                    if hasattr(game, "close"):
                        game.close()                                      # e.g. release the camera
                await transition(fairy, game.frame(), menu.frame())       # app closes, menu opens
        finally:
            try:  # full quit (also Ctrl-C): TV switch-off animation, then everything off
                await tv_off(fairy, menu.frame())
                if fairy:
                    await fairy.power(False)
            except Exception as err:
                print(f"could not switch lights off: {err}", file=sys.stderr)


async def shell(ap: argparse.ArgumentParser, fairy: Fairy) -> None:
    print("Hello Fairy shell. Commands like: color red | image cat.png | text HI | preset fireworks | quit")
    loop = asyncio.get_running_loop()
    while True:
        try:
            line = (await loop.run_in_executor(None, input, "fairy> ")).strip()
        except (EOFError, KeyboardInterrupt):
            print(); return
        if not line:
            continue
        if line in ("q", "quit", "exit"):
            return
        try:
            args = ap.parse_args(shlex.split(line))
            if args.cmd in ("shell", "scan"):
                print("not available inside the shell"); continue
            if args.cmd == "presets":
                print(", ".join(P.PRESETS)); continue
            await run(args, fairy)
        except SystemExit:
            pass
        except Exception as err:
            print(f"error: {err}", file=sys.stderr)


async def amain(a, ap) -> int:
    if a.cmd == "scan":
        log("scanning ...")
        found = await scan(a.timeout, a.all)
        if not found:
            print("nothing found"); return 1
        for dev, rssi, name in found:
            print(f"{dev.address}  {rssi:>4} dBm  {name or '(no name)'}")
        if a.save:
            save_default(found[0][0].address); log("saved default")
        return 0
    if a.cmd == "apps":
        await apps_menu(a)
        return 0
    if a.cmd == "presets":
        for k, v in P.PRESETS.items():
            print(f"{v:>3}  {k}")
        return 0
    if getattr(a, "dry_run", False) and a.cmd in DRY:
        if a.cmd == "text":
            frames = imaging.render_text_pages(a.text, imaging.parse_pixel_color(a.color), size=a.size)
        elif a.cmd == "anim":
            frames = ([imaging.load_frame(a.a, **img_kw(a)), imaging.load_frame(a.b, **img_kw(a))] if a.b
                      else imaging.gif_frames(a.a, 2, **img_kw(a)))
        else:
            frames = [imaging.load_frame(a.file, **img_kw(a))]
        for f in frames:
            show_preview(f, a)
        return 0
    async with Fairy(a.device, log=log) as fairy:
        if a.cmd == "shell":
            await shell(ap, fairy)
        else:
            await run(a, fairy)
    return 0


def main(argv=None) -> int:
    ap = build_parser()
    a = ap.parse_args(argv)
    try:
        return asyncio.run(amain(a, ap))
    except KeyboardInterrupt:
        return 130
    except Exception as err:
        print(f"error: {err}", file=sys.stderr)
        return 1
