"""Weather on the curtain (data: Open-Meteo, free, no API key).

Pages (left/right): 1 icon + temperature, 2 today's high/low, 3 rain chance for the next 6 hours.
"""

from __future__ import annotations

import json
import ssl
import threading
import time
import urllib.parse
import urllib.request

from . import config
from . import protocol as P
from .pong import GLYPHS

W, H = P.WIDTH, P.HEIGHT
GEOCODE_URL = "https://geocoding-api.open-meteo.com/v1/search"
FORECAST_URL = "https://api.open-meteo.com/v1/forecast"
REFRESH_SECONDS = 600
RETRY_SECONDS = 30
CODES = {".": None, "Y": 30, "O": 15, "W": 255, "B": 120, "C": 90, "R": 0, "G": 60}

ICONS = {
    "sun": [
        ".....O.....",
        ".O...O...O.",
        "..O.YYY.O..",
        "...YYYYY...",
        "OOOYYYYYOOO",
        "...YYYYY...",
        "..O.YYY.O..",
        ".O...O...O.",
        ".....O.....",
    ],
    "moon": [
        "....WWW....",
        "..WWW......",
        ".WW........",
        ".WW.....C..",
        ".WW........",
        ".WW...C....",
        "..WWW......",
        "....WWW....",
    ],
    "partly": [
        "..O.O.O....",
        "...YYY.....",
        ".O.YYYYWW..",
        "...YYWWWWWW",
        "....WWWWWWW",
        ".....WWWWW.",
    ],
    "cloud": [
        "...WWW.....",
        "..WWWWW.WW.",
        ".WWWWWWWWWW",
        "WWWWWWWWWWW",
        ".WWWWWWWWW.",
    ],
    "rain": [
        "...WWW.....",
        "..WWWWW.WW.",
        ".WWWWWWWWWW",
        "WWWWWWWWWWW",
        ".WWWWWWWWW.",
        "...........",
        "..B..B..B..",
        ".B..B..B...",
    ],
    "snow": [
        "...WWW.....",
        "..WWWWW.WW.",
        ".WWWWWWWWWW",
        "WWWWWWWWWWW",
        ".WWWWWWWWW.",
        "...........",
        "..C..C..C..",
        ".C..C..C..C",
    ],
    "thunder": [
        "...WWW.....",
        "..WWWWW.WW.",
        ".WWWWWWWWWW",
        "WWWWWWWWWWW",
        ".WWWWWWWWW.",
        "......YY...",
        ".....YY....",
        "....YYYY...",
        ".....YY....",
    ],
    "fog": [
        "..WWWWWWW..",
        "...........",
        ".WWWWWWWWW.",
        "...........",
        "..WWWWWWW..",
        "...........",
        "WWWWWWWWWWW",
    ],
}
ARROWS = {"up": ("010", "111", "111"), "down": ("111", "111", "010")}


def icon_for(code: int, is_day: bool = True) -> str:
    """WMO weather code -> icon name."""
    if code in (0, 1):
        return "sun" if is_day else "moon"
    if code == 2:
        return "partly" if is_day else "cloud"
    if code == 3:
        return "cloud"
    if code in (45, 48):
        return "fog"
    if 51 <= code <= 67 or 80 <= code <= 82:
        return "rain"
    if 71 <= code <= 77 or code in (85, 86):
        return "snow"
    if code >= 95:
        return "thunder"
    return "cloud"


def temp_color(t: float) -> int:
    """Cold = blue, warm = red."""
    if t < 0:
        return 120
    if t < 10:
        return 90
    if t < 20:
        return 60
    if t < 28:
        return 30
    return 0


# ---------------------------------------------------------------------- data
def _get(url: str, params: dict, timeout: float = 8.0) -> dict:
    req = urllib.request.Request(url + "?" + urllib.parse.urlencode(params),
                                 headers={"User-Agent": "hellofairy/0.1"})
    try:  # python.org builds on macOS ship without root certificates; certifi has them
        import certifi
        ctx = ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        ctx = ssl.create_default_context()
    with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
        return json.load(resp)


def geocode(city: str) -> dict:
    data = _get(GEOCODE_URL, {"name": city, "count": 1, "language": "en", "format": "json"})
    results = data.get("results") or []
    if not results:
        raise LookupError(f"city not found: {city!r}")
    r = results[0]
    return {"name": r["name"], "lat": r["latitude"], "lon": r["longitude"]}


def parse_forecast(data: dict) -> dict:
    cur = data["current"]
    daily = data["daily"]
    hourly = data["hourly"]
    start = next((i for i, t in enumerate(hourly["time"]) if t[:13] >= cur["time"][:13]), 0)
    rain = [int(v or 0) for v in hourly["precipitation_probability"][start : start + 6]]
    return {
        "temp": round(cur["temperature_2m"]),
        "code": int(cur["weather_code"]),
        "is_day": bool(cur.get("is_day", 1)),
        "wind": cur.get("wind_speed_10m"),
        "high": round(daily["temperature_2m_max"][0]),
        "low": round(daily["temperature_2m_min"][0]),
        "rain": rain + [0] * (6 - len(rain)),
    }


def fetch(lat: float, lon: float) -> dict:
    return parse_forecast(_get(FORECAST_URL, {
        "latitude": lat, "longitude": lon, "timezone": "auto", "forecast_days": 2,
        "current": "temperature_2m,weather_code,is_day,wind_speed_10m",
        "hourly": "precipitation_probability",
        "daily": "temperature_2m_max,temperature_2m_min",
    }))


# ---------------------------------------------------------------------- rendering
def _blit(f: list[int], rows: list[str], x0: int, y0: int) -> None:
    for dy, row in enumerate(rows):
        for dx, ch in enumerate(row):
            color = CODES[ch]
            if color is not None and 0 <= x0 + dx < W and 0 <= y0 + dy < H:
                f[(y0 + dy) * W + x0 + dx] = color


def _number(f: list[int], value: int, y0: int, color: int, x0: int | None = None) -> None:
    text = str(value)
    width = sum(len(GLYPHS[c][0]) for c in text) + len(text) - 1
    x = (W - width - 2) // 2 if x0 is None else x0   # leave room for the degree dot
    for ch in text:
        for dy, row in enumerate(GLYPHS[ch]):
            for dx, bit in enumerate(row):
                if bit == "1":
                    f[(y0 + dy) * W + x + dx] = color
        x += len(GLYPHS[ch][0]) + 1
    if x < W:
        f[y0 * W + x] = color                       # degree sign


def _page_dots(f: list[int], page: int, pages: int = 3) -> None:
    x0 = (W - (2 * pages - 1)) // 2
    for i in range(pages):
        f[(H - 1) * W + x0 + 2 * i] = 30 if i == page else 120


def render(data: dict, page: int) -> list[int]:
    f = [P.PIXEL_OFF] * (W * H)
    if page == 0:
        icon = ICONS[icon_for(data["code"], data["is_day"])]
        _blit(f, icon, (W - len(icon[0])) // 2, 1 + (9 - len(icon)) // 2)
        _number(f, data["temp"], 12, temp_color(data["temp"]))
    elif page == 1:
        for top, key, arrow, acolor in ((3, "high", "up", 0), (12, "low", "down", 120)):
            _blit(f, [r.replace("1", "R" if arrow == "up" else "B").replace("0", ".") for r in ARROWS[arrow]], 2, top + 1)
            _number(f, data[key], top, temp_color(data[key]), x0=7)
    else:
        for i, pct in enumerate(data["rain"][:6]):
            height = round(max(0, min(100, pct)) / 100 * 15)
            x = 2 + 3 * i
            for dy in range(max(1, height)):                 # at least a stub, so 0% still shows
                for dx in (0, 1):
                    f[(17 - dy) * W + x + dx] = 120 if height else 90
        for x in range(1, W - 1):
            f[18 * W + x] = 15                              # baseline
    _page_dots(f, page)
    return f


def loading_frame(t: int) -> list[int]:
    f = [P.PIXEL_OFF] * (W * H)
    for i in range(3):
        f[10 * W + 7 + 3 * i] = 90 if (t // 1) % 3 == i else 120
    return f


def error_frame() -> list[int]:
    f = [P.PIXEL_OFF] * (W * H)
    for i in range(10):
        f[(5 + i) * W + 5 + i] = f[(5 + i) * W + 14 - i] = 0
    return f


class Weather:
    """Arcade-runner 'game': left/right = page, enter = refresh now."""

    tick = 1.0
    hint = "left/right page · enter/r refresh · q menu"

    def __init__(self, city: str | None = None, clock=time.monotonic, threaded: bool = True,
                 fetcher=fetch, geocoder=geocode, save=True):
        self.city_query = city
        self.clock, self.threaded = clock, threaded
        self.fetcher, self.geocoder, self.save = fetcher, geocoder, save
        saved = config.load().get("weather")
        self.loc = saved if isinstance(saved, dict) and not city else None
        self.data: dict | None = None
        self.error: str | None = None
        self.page = 0
        self.t = 0
        self._loading = False
        self._next_fetch = 0.0

    def reset(self) -> None:
        self._next_fetch = 0.0

    def key(self, name: str) -> None:
        if name in ("left", "up"):
            self.page = (self.page - 1) % 3
        elif name in ("right", "down"):
            self.page = (self.page + 1) % 3
        elif name == "enter":
            self.reset()

    def step(self) -> None:
        self.t += 1
        if not self._loading and self.clock() >= self._next_fetch:
            self._loading = True
            if self.threaded:
                threading.Thread(target=self._work, daemon=True).start()
            else:
                self._work()

    def _work(self) -> None:
        try:
            if self.city_query:
                self.loc = self.geocoder(self.city_query)
                if self.save:
                    config.update(weather=self.loc)
                self.city_query = None
            if not self.loc:
                raise LookupError("no city set - run: fairy weather --city YOURCITY")
            self.data = self.fetcher(self.loc["lat"], self.loc["lon"])
            self.error = None
            self._next_fetch = self.clock() + REFRESH_SECONDS
        except Exception as err:
            self.error = str(err) or type(err).__name__
            self._next_fetch = self.clock() + RETRY_SECONDS
        finally:
            self._loading = False

    def status(self) -> str:
        where = (self.loc or {}).get("name", "?")
        if self.error and not self.data:
            return f"weather: {self.error}"
        if not self.data:
            return f"weather {where}: loading..."
        d = self.data
        stale = f"  (update failed: {self.error})" if self.error else ""
        return (f"{where}: {d['temp']}° {icon_for(d['code'], d['is_day'])}  "
                f"high {d['high']}° low {d['low']}°  rain {max(d['rain'])}%  page {self.page + 1}/3{stale}")

    def frame(self) -> list[int]:
        if self.data:
            return render(self.data, self.page)
        return error_frame() if self.error else loading_frame(self.t)
