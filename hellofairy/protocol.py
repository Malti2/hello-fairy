"""Pure Hello Fairy packet building / decoding (no BLE, fully unit-testable).

Protocol knowledge comes from nzrutman/hello_fairy_ble and the Hello Fairy app.
Packets: ``AA <cmd> <payload_len> <payload...> <checksum>``, checksum = sum(prev) & 0xFF.
"""

from __future__ import annotations

import colorsys
from collections.abc import Iterable, Sequence

SERVICE_UUID = "49535343-fe7d-4ae5-8fa9-9fafd205e455"
COMMAND_UUID = "49535343-8841-43f4-a8d4-ecbe34729bb3"
NOTIFY_UUID = "49535343-1E4D-4BD9-BA61-23C647249616"
NAME_PREFIX = "Hello Fairy"

HEADER = 0xAA
WIDTH = HEIGHT = 20
PIXEL_COUNT = WIDTH * HEIGHT
PIXEL_OFF = 0xFE
PIXEL_WHITE = 0xFF
MAX_PIXELS_PER_PACKET = 79  # 242-byte GATT value -> needs ATT MTU >= 245
DA_PACKET_BYTES = 242

PRESETS = {
    "blue-white-dissolve": 41,
    "blue-sparkle": 56,
    "white-sparkle": 57,
    "blue-pink-sparkle": 8,
    "fireworks": 17,
    "xmas": 18,
    "candy-cane": 50,
    "halloween": 20,
    "red-gold": 40,
    "july-4th": 39,
    "valentine": 46,
    "st-patrick": 47,
    "may-day": 48,
    "snow-day": 54,
}

MOVEMENTS = {
    "still": 0, "up": 1, "down": 2, "left": 3, "right": 4,
    "blink": 5, "breathe": 6,
    "loop-up": 7, "loop-down": 8, "loop-left": 9, "loop-right": 10,
}


def checksum(data: Iterable[int]) -> int:
    return sum(data) & 0xFF


def build_packet(cmd: int, payload: Sequence[int] = ()) -> bytes:
    if not 0 <= cmd <= 0xFF or len(payload) > 0xFF:
        raise ValueError("bad packet")
    body = [HEADER, cmd, len(payload), *payload]
    return bytes([*body, checksum(body)])


# --- light-string / generic commands -------------------------------------------------

def power_packet(on: bool) -> bytes:
    return build_packet(0x02, [1 if on else 0])


def color_packet(h: int, s: int, v: int) -> bytes:
    """h 0-359, s/v 0-100 percent."""
    h = max(0, min(359, int(h)))
    s = max(0, min(100, int(s))) * 10
    v = max(0, min(100, int(v))) * 10
    return build_packet(0x03, [0x01, h >> 8, h & 0xFF, s >> 8, s & 0xFF, v >> 8, v & 0xFF])


def preset_packet(preset: int, brightness: int) -> bytes:
    if not 1 <= preset <= 58:
        raise ValueError("preset must be 1..58")
    b = max(0, min(100, int(brightness))) * 10
    return build_packet(0x03, [0x02, preset, b >> 8, b & 0xFF])


def info_request() -> bytes:
    return build_packet(0x00)


def status_request() -> bytes:
    return build_packet(0x01)


# --- pixel (DIY) commands ------------------------------------------------------------

def d0_packet(action: int) -> bytes:
    if action not in (0x00, 0x01, 0x03, 0x04):
        raise ValueError("unsupported D0 sub-command")
    return build_packet(0xD0, [0x00, 0x64, 0x64, action])


def pixel_index(x: int, y: int) -> int:
    if not (0 <= x < WIDTH and 0 <= y < HEIGHT):
        raise ValueError("pixel out of range")
    return x * HEIGHT + y  # device is column-major


def validate_color_byte(c: int) -> int:
    if type(c) is not int or not (0 <= c <= 180 or c in (PIXEL_OFF, PIXEL_WHITE)):
        raise ValueError("color byte must be 0..180, 254 (off) or 255 (white)")
    return c


def frame_to_da_packets(frame: Sequence[int], slot: int = 1) -> list[bytes]:
    """400 row-major color bytes -> 6 DA packets (5x79 + 5 pixels)."""
    if len(frame) != PIXEL_COUNT:
        raise ValueError("frame must have 400 pixels")
    entries = []
    for y in range(HEIGHT):
        for x in range(WIDTH):
            entries.append((pixel_index(x, y), validate_color_byte(frame[y * WIDTH + x])))
    entries.sort()
    packets = []
    for i in range(0, len(entries), MAX_PIXELS_PER_PACKET):
        payload = [slot]
        for idx, col in entries[i : i + MAX_PIXELS_PER_PACKET]:
            payload += [idx >> 8, idx & 0xFF, col]
        packets.append(build_packet(0xDA, payload))
    assert [len(p) for p in packets] == [DA_PACKET_BYTES] * 5 + [20]
    return packets


def single_image_sequence(frame: Sequence[int]) -> list[tuple[str, bytes, float]]:
    """(label, packet, delay-after-seconds) as captured from the official app."""
    seq = [
        ("clear", d0_packet(0x03), 0.0165),
        ("draw mode", d0_packet(0x00), 0.25),
    ]
    packets = frame_to_da_packets(frame)
    for n, p in enumerate(packets, 1):
        seq.append((f"pixels {n}/{len(packets)}", p, 0.30 if n < len(packets) else 1.20))
    seq += [("finish", d0_packet(0x04), 0.02), ("apply", d0_packet(0x01), 0.20)]
    return seq


def two_picture_sequence(frames: Sequence[Sequence[int]]) -> list[tuple[str, bytes, float]]:
    """Experimental blink/breathe between two pictures (captured sequence)."""
    if len(frames) != 2:
        raise ValueError("exactly two frames")
    seq = [("init", bytes.fromhex("aad0040564640752"), 0.025)]
    for slot, frame in enumerate(frames, 1):
        seq.append((f"slot {slot} begin", build_packet(0xD7, [slot, 0]), 0.025))
        if slot == 1:
            seq.append(("upload settings", bytes.fromhex("aad004056464004b"), 0.25))
        packets = frame_to_da_packets(frame, slot)
        for n, p in enumerate(packets, 1):
            seq.append((f"slot {slot} pixels {n}/{len(packets)}", p, 0.30))
        seq.append((f"slot {slot} end", build_packet(0xD7, [slot, 2]), 0.025))
    seq += [("playback", bytes.fromhex("aad004056464024d"), 0.025),
            ("trailing", bytes.fromhex("aadc010087"), 0.20)]
    return seq


def playback_packets(kind: str, movement: str, speed: int, brightness: int) -> list[bytes]:
    if movement not in MOVEMENTS:
        raise ValueError(f"movement must be one of {', '.join(MOVEMENTS)}")
    for v in (speed, brightness):
        if not 0 <= v <= 100:
            raise ValueError("speed/brightness must be 0..100")
    if kind == "animation":
        if movement not in ("blink", "breathe"):
            raise ValueError("animation supports blink or breathe")
        d = int(movement == "breathe")
        return [build_packet(0xD0, [d, brightness, speed, 2]), build_packet(0xDC, [d])]
    return [build_packet(0xD0, [MOVEMENTS[movement], brightness, speed, 1])]


# --- colour conversion ---------------------------------------------------------------

def hue_byte_to_rgb(c: int) -> tuple[int, int, int]:
    if c == PIXEL_OFF:
        return (0, 0, 0)
    if c == PIXEL_WHITE:
        return (255, 255, 255)
    r, g, b = colorsys.hsv_to_rgb(min(c, 180) * 2 / 360, 1, 1)
    return (round(r * 255), round(g * 255), round(b * 255))


def rgb_to_pixel_byte(r: int, g: int, b: int, *, dark: float = 0.18, white: float = 0.18) -> int:
    """Only hue/white/off exist per pixel; brightness & saturation are lost."""
    h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
    if v < dark:
        return PIXEL_OFF
    if s < white:
        return PIXEL_WHITE
    return min(180, round(h * 360 / 2))


# --- notification decoding -----------------------------------------------------------

def _valid(data: bytes, cmd: int) -> bool:
    return (len(data) >= 4 and data[0] == HEADER and data[1] == cmd
            and data[2] == len(data) - 4 and checksum(data[:-1]) == data[-1])


def is_ack(data: bytes) -> int | None:
    """Return the acknowledged command, or None."""
    if len(data) == 4 and data[0] == HEADER and data[2] == 0 and checksum(data[:3]) == data[3]:
        return data[1]
    return None


def decode_status(data: bytes) -> dict | None:
    if len(data) < 9 or not _valid(data, 0x01):
        return None
    p = data[3:-1]
    if p[3] not in (0, 1):
        return None
    mode = p[4]
    if (mode == 1 and len(p) < 11) or (mode == 2 and len(p) < 8):
        return None
    out = {"power": bool(p[3]), "mode": mode, "countdown_seconds": int.from_bytes(p[:3], "big")}
    if mode == 1:
        h, s, v = (int.from_bytes(p[i : i + 2], "big") for i in (5, 7, 9))
        out.update(hue=h, saturation=s / 10, brightness=v / 10)
    elif mode == 2:
        out.update(preset=p[5], brightness=int.from_bytes(p[6:8], "big"))
    return out


def decode_device_info(data: bytes) -> dict | None:
    if len(data) < 31 or not _valid(data, 0x00):
        return None
    p = data[3:-1]
    try:
        return {
            "firmware": p[:5].decode("ascii"),
            "model": p[5:20].split(b"\x00", 1)[0].decode("ascii"),
            "led_count": int.from_bytes(p[20:22], "big"),
            "columns": p[22], "rows": p[24], "diy_type": p[26],
        }
    except UnicodeDecodeError:
        return None


def delta_packets(changes: dict[int, int], slot: int = 1) -> list[bytes]:
    """{device_index: color_byte} -> DA packets with only those pixels (draw mode)."""
    items = sorted(changes.items())
    out = []
    for i in range(0, len(items), MAX_PIXELS_PER_PACKET):
        payload = [slot]
        for idx, col in items[i : i + MAX_PIXELS_PER_PACKET]:
            validate_color_byte(col)
            payload += [idx >> 8, idx & 0xFF, col]
        out.append(build_packet(0xDA, payload))
    return out


def frame_to_index_map(frame: Sequence[int]) -> dict[int, int]:
    return {pixel_index(x, y): frame[y * WIDTH + x] for y in range(HEIGHT) for x in range(WIDTH)}
