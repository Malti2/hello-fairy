import pytest

from hellofairy import config, protocol as P
from hellofairy import weather as wx

SAMPLE = {
    "current": {"time": "2026-11-07T17:15", "temperature_2m": 3.6, "weather_code": 63,
                "is_day": 0, "wind_speed_10m": 12.0},
    "daily": {"temperature_2m_max": [6.2, 7], "temperature_2m_min": [-1.4, 0]},
    "hourly": {"time": [f"2026-11-07T{h:02d}:00" for h in range(24)],
               "precipitation_probability": [0] * 17 + [10, 30, None, 90, 100, 5] + [0]},
}


def test_parse_forecast():
    d = wx.parse_forecast(SAMPLE)
    assert d["temp"] == 4 and d["high"] == 6 and d["low"] == -1 and d["code"] == 63
    assert d["is_day"] is False
    assert d["rain"] == [10, 30, 0, 90, 100, 5]            # starts at the current hour, None -> 0


def test_icon_mapping():
    assert wx.icon_for(0, True) == "sun" and wx.icon_for(0, False) == "moon"
    assert wx.icon_for(2, True) == "partly" and wx.icon_for(3) == "cloud"
    assert wx.icon_for(45) == "fog" and wx.icon_for(53) == "rain" and wx.icon_for(81) == "rain"
    assert wx.icon_for(73) == "snow" and wx.icon_for(86) == "snow" and wx.icon_for(96) == "thunder"
    assert set(wx.ICONS) >= {wx.icon_for(c) for c in (0, 2, 3, 45, 61, 71, 95)}


def test_temp_colors_are_ordered_cold_to_hot():
    assert [wx.temp_color(t) for t in (-5, 5, 15, 25, 35)] == [120, 90, 60, 30, 0]


@pytest.mark.parametrize("temp", [-12, -3, 0, 7, 23, 38])
@pytest.mark.parametrize("page", [0, 1, 2])
def test_all_pages_render_valid_frames(temp, page):
    data = {"temp": temp, "code": 61, "is_day": True, "wind": 5, "high": temp + 3, "low": temp - 4,
            "rain": [0, 20, 50, 80, 100, 10]}
    f = wx.render(data, page)
    assert len(f) == 400 and all(P.validate_color_byte(c) is not None for c in f)
    assert any(c != P.PIXEL_OFF for c in f)


def test_every_icon_renders_and_fits():
    for name, rows in wx.ICONS.items():
        assert len({len(r) for r in rows}) == 1 and len(rows[0]) <= 12 and len(rows) <= 9, name
        data = {"temp": 5, "code": 0, "is_day": True, "wind": 0, "high": 6, "low": 1, "rain": [0] * 6}
        f = [P.PIXEL_OFF] * 400
        wx._blit(f, rows, 4, 1)
        assert any(c != P.PIXEL_OFF for c in f), name


@pytest.fixture
def cfg(tmp_path, monkeypatch):
    monkeypatch.setenv("HELLOFAIRY_CONFIG", str(tmp_path / "c.json"))
    return tmp_path / "c.json"


class Clock:
    t = 0.0

    def __call__(self):
        return self.t


def test_weather_flow_city_saved_and_refresh(cfg):
    calls = []
    clk = Clock()
    w = wx.Weather("Testville", clock=clk, threaded=False, save=True,
                   geocoder=lambda c: {"name": c, "lat": 1.0, "lon": 2.0},
                   fetcher=lambda la, lo: calls.append((la, lo)) or wx.parse_forecast(SAMPLE))
    assert w.frame() == wx.loading_frame(0)
    w.step()
    assert calls == [(1.0, 2.0)] and w.data and "Testville" in w.status()
    assert config.load()["weather"]["name"] == "Testville"
    w.step()
    assert len(calls) == 1                               # no refetch before 10 minutes
    clk.t += 601
    w.step()
    assert len(calls) == 2
    # a later run without --city uses the saved location
    w2 = wx.Weather(clock=clk, threaded=False, fetcher=lambda la, lo: calls.append((la, lo)) or wx.parse_forecast(SAMPLE))
    w2.step()
    assert calls[-1] == (1.0, 2.0)


def test_weather_without_city_shows_error(cfg):
    w = wx.Weather(clock=Clock(), threaded=False)
    w.step()
    assert "no city" in w.status() and w.frame() == wx.error_frame()


def test_weather_failure_keeps_old_data_and_retries(cfg):
    clk = Clock()
    ok = {"v": True}

    def fetcher(la, lo):
        if not ok["v"]:
            raise OSError("offline")
        return wx.parse_forecast(SAMPLE)

    w = wx.Weather("X", clock=clk, threaded=False, save=False,
                   geocoder=lambda c: {"name": c, "lat": 0, "lon": 0}, fetcher=fetcher)
    w.step()
    ok["v"] = False
    clk.t += 700
    w.step()
    assert w.data and w.error == "offline" and "update failed" in w.status()
    clk.t += 31
    ok["v"] = True
    w.step()
    assert w.error is None


def test_page_navigation_wraps(cfg):
    w = wx.Weather(clock=Clock(), threaded=False)
    w.key("right"); w.key("right"); w.key("right")
    assert w.page == 0
    w.key("left")
    assert w.page == 2


def test_geocode_parses_response(monkeypatch):
    monkeypatch.setattr(wx, "_get", lambda url, params, timeout=8: {"results": [{"name": "Berlin", "latitude": 52.52, "longitude": 13.4}]})
    assert wx.geocode("Berlin") == {"name": "Berlin", "lat": 52.52, "lon": 13.4}
    monkeypatch.setattr(wx, "_get", lambda url, params, timeout=8: {})
    with pytest.raises(LookupError):
        wx.geocode("Nowhere")
