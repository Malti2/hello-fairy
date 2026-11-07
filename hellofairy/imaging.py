"""Image/text -> 20x20 Hello Fairy frame, plus terminal/PNG preview."""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont, ImageOps

from .protocol import (HEIGHT, PIXEL_COUNT, PIXEL_OFF, PIXEL_WHITE, WIDTH,
                       hue_byte_to_rgb, rgb_to_pixel_byte)

COLOR_NAMES = {
    "red": 0, "orange": 15, "yellow": 30, "lime": 45, "green": 60, "cyan": 90,
    "blue": 120, "purple": 140, "magenta": 150, "pink": 165,
    "white": PIXEL_WHITE, "off": PIXEL_OFF, "black": PIXEL_OFF,
}


def parse_pixel_color(text: str) -> int:
    """Name, '#rrggbb', or raw byte 0-180 -> device color byte."""
    t = text.strip().lower()
    if t in COLOR_NAMES:
        return COLOR_NAMES[t]
    if t.startswith("#") and len(t) == 7:
        r, g, b = (int(t[i : i + 2], 16) for i in (1, 3, 5))
        return rgb_to_pixel_byte(r, g, b, dark=0.05, white=0.1)
    if t.isdigit() and 0 <= int(t) <= 180:
        return int(t)
    raise ValueError(f"unknown color {text!r} (name, #rrggbb or 0-180)")


def load_frame(path: str | Path, *, fit: str = "contain", dark: float = 0.18,
               white: float = 0.18, boost: float = 1.0, frame_index: int = 0) -> list[int]:
    """Load any Pillow-readable image into 400 row-major color bytes."""
    img = Image.open(path)
    try:
        img.seek(frame_index)
    except EOFError:
        pass
    img = img.convert("RGBA")
    bg = Image.new("RGBA", img.size, (0, 0, 0, 255))
    img = Image.alpha_composite(bg, img).convert("RGB")
    size = (WIDTH, HEIGHT)
    if fit == "stretch":
        img = img.resize(size, Image.LANCZOS)
    elif fit == "cover":
        img = ImageOps.fit(img, size, Image.LANCZOS)
    elif fit == "contain":
        img = ImageOps.pad(img, size, Image.LANCZOS, color=(0, 0, 0))
    else:
        raise ValueError("fit must be contain, cover or stretch")
    if boost != 1.0:
        from PIL import ImageEnhance
        img = ImageEnhance.Brightness(img).enhance(boost)
    return [rgb_to_pixel_byte(*img.getpixel((x, y)), dark=dark, white=white)
            for y in range(HEIGHT) for x in range(WIDTH)]


def gif_frames(path: str | Path, limit: int = 2, **kw) -> list[list[int]]:
    img = Image.open(path)
    n = getattr(img, "n_frames", 1)
    idx = [round(i * (n - 1) / max(1, limit - 1)) for i in range(limit)]
    return [load_frame(path, frame_index=i, **kw) for i in idx]


def render_text_pages(text: str, color: int = 0, *, size: int = 9, spacing: int = 1) -> list[list[int]]:
    """Render text with Pillow's built-in font, split into 20px-wide pages."""
    font = ImageFont.load_default(size=size)
    probe = Image.new("1", (1, 1))
    left, top, right, bottom = ImageDraw.Draw(probe).textbbox((0, 0), text, font=font)
    w, h = max(1, right - left), max(1, bottom - top)
    canvas = Image.new("1", (w + 2 * spacing, h), 0)
    ImageDraw.Draw(canvas).text((spacing - left, -top), text, fill=1, font=font)
    pages = []
    for x0 in range(0, canvas.width, WIDTH):
        page = Image.new("1", (WIDTH, HEIGHT), 0)
        chunk = canvas.crop((x0, 0, min(canvas.width, x0 + WIDTH), canvas.height))
        page.paste(chunk, ((WIDTH - chunk.width) // 2, (HEIGHT - canvas.height) // 2))
        pages.append([color if page.getpixel((x, y)) else PIXEL_OFF
                      for y in range(HEIGHT) for x in range(WIDTH)])
    return pages


def preview_ansi(frame: list[int]) -> str:
    lines = []
    for y in range(HEIGHT):
        row = []
        for x in range(WIDTH):
            r, g, b = hue_byte_to_rgb(frame[y * WIDTH + x])
            row.append(f"\x1b[48;2;{r};{g};{b}m  ")
        lines.append("".join(row) + "\x1b[0m")
    return "\n".join(lines)


def save_preview(frame: list[int], path: str | Path, scale: int = 16) -> None:
    img = Image.new("RGB", (WIDTH, HEIGHT))
    img.putdata([hue_byte_to_rgb(c) for c in frame])
    img.resize((WIDTH * scale, HEIGHT * scale), Image.NEAREST).save(path)
