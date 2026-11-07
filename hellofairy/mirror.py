"""Live webcam mirror on the 20x20 curtain.

The curtain has one colour *byte* per pixel (hue, white or off), so there are four looks
(left/right switches): thermal (brightness -> blue..red), colour (real hues), silhouette
(you in colour, background off; space re-captures the background) and motion.
Bluetooth can't carry a whole video frame per tick, so only the biggest pixel changes are
sent each step (`budget`) and small flicker is ignored (hysteresis).
"""

from __future__ import annotations

import math
import threading
import time

import numpy as np

from . import protocol as P
from .weather import error_frame

W, H = P.WIDTH, P.HEIGHT
OFF, WHITE = P.PIXEL_OFF, P.PIXEL_WHITE
MODES = ("thermal", "color", "silhouette", "motion")
THRESHOLD = 6          # minimum hue change (of 180) before a pixel is re-sent
CAMERA_HELP = ("camera not available - allow your terminal under System Settings > Privacy & "
               "Security > Camera, close other apps using it, then start again (or use --demo)")


# ---------------------------------------------------------------------- frame sources
class DemoSource:
    """Synthetic camera: a bright coloured blob bouncing over a dim gradient."""

    def __init__(self):
        self.t0 = time.monotonic()

    def read(self):
        t = time.monotonic() - self.t0
        h, w = 120, 160
        yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
        img = np.zeros((h, w, 3), np.float32)
        img[..., 0] = 40 + 60 * xx / w                      # dim blue->purple gradient (BGR)
        img[..., 2] = 30 + 40 * yy / h
        cx, cy = w / 2 + 50 * math.sin(t * 1.3), h / 2 + 35 * math.cos(t * 0.9)
        d = np.hypot(xx - cx, yy - cy)
        blob = np.clip(1 - d / 28, 0, 1)[..., None]
        img = img * (1 - blob) + np.array([40, 220, 255], np.float32) * blob   # yellow-ish blob
        return img.astype(np.uint8)

    def close(self):
        pass


class CvSource:
    """OpenCV camera, read in a background thread so the game loop never blocks."""

    def __init__(self, index: int = 0):
        import cv2
        self.cv2 = cv2
        self.cap = cv2.VideoCapture(index)             # opened on the main thread (macOS permission)
        if not self.cap.isOpened():
            raise RuntimeError(CAMERA_HELP)
        self.latest = None
        self.stop = threading.Event()
        self.thread = threading.Thread(target=self._loop, daemon=True)
        self.thread.start()

    def _loop(self):
        while not self.stop.is_set():
            ok, frame = self.cap.read()
            if ok:
                self.latest = frame
            else:
                time.sleep(0.05)

    def read(self):
        return self.latest

    def close(self):
        self.stop.set()
        self.thread.join(timeout=1)
        self.cap.release()


# ---------------------------------------------------------------------- image -> 20x20
def to_grid(bgr: np.ndarray, mirror: bool = True) -> np.ndarray:
    """BGR camera frame -> 20x20x3 RGB float array (0..1): mirrored, centre-cropped, area-averaged."""
    import cv2
    h, w = bgr.shape[:2]
    s = min(h, w)
    y0, x0 = (h - s) // 2, (w - s) // 2
    sq = bgr[y0:y0 + s, x0:x0 + s]
    if mirror:
        sq = sq[:, ::-1]
    small = cv2.resize(np.ascontiguousarray(sq), (W, H), interpolation=cv2.INTER_AREA)
    return small[..., ::-1].astype(np.float32) / 255.0


def gray_of(rgb: np.ndarray) -> np.ndarray:
    return rgb @ np.array([0.299, 0.587, 0.114], np.float32)


def thermal_map(gray: np.ndarray, gain: float = 1.0) -> np.ndarray:
    """Brightness -> colour: dark off, then blue, cyan, green, yellow, red, brightest white."""
    lo, hi = np.percentile(gray, 3), np.percentile(gray, 97)
    v = np.clip((gray - lo) / max(hi - lo, 0.2), 0, 1) * gain
    out = np.full(gray.shape, OFF, np.int32)
    lit = v >= 0.1
    t = np.clip((v - 0.1) / 0.87, 0, 1)
    out[lit] = np.round(120 * (1 - t[lit])).astype(np.int32)
    out[v >= 0.97] = WHITE
    return out


def color_map(rgb: np.ndarray, boost: float = 1.6) -> np.ndarray:
    """Real hues (saturation boosted); dark pixels off, washed-out pixels white."""
    import cv2
    hsv = cv2.cvtColor((np.clip(rgb, 0, 1) * 255).astype(np.uint8).reshape(1, -1, 3), cv2.COLOR_RGB2HSV)
    hsv = hsv.reshape(H, W, 3).astype(np.float32)
    hue, sat, val = hsv[..., 0], np.clip(hsv[..., 1] / 255 * boost, 0, 1), hsv[..., 2] / 255
    out = np.clip(np.round(hue), 0, 180).astype(np.int32)
    out[sat < 0.25] = WHITE
    out[val < 0.18] = OFF
    return out


def silhouette_map(rgb: np.ndarray, background: np.ndarray, thr: float = 0.18) -> np.ndarray:
    """You in colour, background off. Compares full RGB so same-brightness colours still count."""
    out = color_map(rgb)
    out[np.linalg.norm(rgb - background, axis=-1) < thr] = OFF
    return out


def motion_map(gray: np.ndarray, previous: np.ndarray, gain: float = 6.0) -> np.ndarray:
    d = np.clip(np.abs(gray - previous) * gain, 0, 1)
    out = np.full(gray.shape, OFF, np.int32)
    on = d >= 0.15
    out[on] = np.round(120 * (1 - d[on])).astype(np.int32)    # small motion blue ... big motion red
    return out


def distance(a: int, b: int) -> int:
    """How different two colour bytes look (0 = identical, 90 = opposite)."""
    if a == b:
        return 0
    if a in (OFF, WHITE) or b in (OFF, WHITE):
        return 90
    d = abs(a - b)
    return min(d, 180 - d)


# ---------------------------------------------------------------------- the 'game'
class Mirror:
    space_key = True            # space re-captures the background
    tick = 0.12
    hint = "left/right look (thermal/color/silhouette/motion) · space background · r reset · p pause · q menu"

    def __init__(self, source=None, mode: str = "thermal", budget: int = P.MAX_PIXELS_PER_PACKET,
                 camera: int = 0, demo: bool = False):
        self.error: str | None = None
        self.source = source
        if self.source is None:
            try:
                self.source = DemoSource() if demo else CvSource(camera)
            except Exception as err:                       # no camera / no permission / no OpenCV
                self.error = str(err) or CAMERA_HELP
        self.mode_i = MODES.index(mode)
        self.budget = budget
        self.reset()

    # -- lifecycle -----------------------------------------------------------------
    def reset(self) -> None:
        self.shown = [OFF] * (W * H)
        self.smooth: np.ndarray | None = None
        self.background: np.ndarray | None = None      # RGB reference for silhouette mode
        self.previous: np.ndarray | None = None
        self.steps = 0
        self.changed = 0
        self.have_frame = False

    def close(self) -> None:
        if self.source:
            self.source.close()
            self.source = None

    @property
    def mode(self) -> str:
        return MODES[self.mode_i]

    def key(self, name: str) -> None:
        if name in ("right", "down"):
            self.mode_i = (self.mode_i + 1) % len(MODES)
        elif name in ("left", "up"):
            self.mode_i = (self.mode_i - 1) % len(MODES)
        elif name == "space":
            self.background = None             # re-captured from the next frame

    def status(self) -> str:
        if self.error:
            return self.error
        if not self.have_frame:
            return "waiting for camera..."
        return f"mode {self.mode}  sent {self.changed} pixels/step"

    # -- processing ----------------------------------------------------------------
    def target(self) -> np.ndarray | None:
        bgr = self.source.read() if self.source else None
        if bgr is None:
            return None
        self.have_frame = True
        rgb = to_grid(bgr)
        # average a little over time to calm sensor noise
        self.smooth = rgb if self.smooth is None else 0.5 * self.smooth + 0.5 * rgb
        rgb, gray = self.smooth, gray_of(self.smooth)
        if self.background is None:
            self.background = rgb.copy()
        prev = self.previous if self.previous is not None else gray
        self.previous = gray.copy()
        mode = self.mode
        if mode == "thermal":
            return thermal_map(gray)
        if mode == "color":
            return color_map(rgb)
        if mode == "silhouette":
            return silhouette_map(rgb, self.background)
        return motion_map(gray, prev)

    def step(self) -> None:
        self.steps += 1
        tgt = self.target()
        if tgt is None:
            return
        flat = [int(v) for v in tgt.reshape(-1)]
        ranked = sorted(((distance(self.shown[i], flat[i]), i) for i in range(W * H)), reverse=True)
        n = 0
        for dist, i in ranked[: self.budget]:
            if dist < THRESHOLD:
                break
            self.shown[i] = flat[i]
            n += 1
        self.changed = n

    def frame(self) -> list[int]:
        return error_frame() if self.error else list(self.shown)
