import numpy as np
import pytest

cv2 = pytest.importorskip("cv2")

from hellofairy import protocol as P
from hellofairy.mirror import (OFF, THRESHOLD, WHITE, DemoSource, Mirror, color_map, distance, gray_of,
                               motion_map, silhouette_map, thermal_map, to_grid)


class FakeSource:
    def __init__(self, frame=None):
        self.frame = frame
        self.closed = False

    def read(self):
        return self.frame

    def close(self):
        self.closed = True


def bgr(color, size=(120, 160)):
    img = np.zeros((*size, 3), np.uint8)
    img[:] = color[::-1]            # given as RGB
    return img


def test_to_grid_crops_square_mirrors_and_averages():
    img = np.zeros((120, 160, 3), np.uint8)
    img[:, :60] = 255                                   # white band on the LEFT of the raw image
    g = to_grid(img)
    assert g.shape == (20, 20, 3)
    # centre crop keeps x 20..140; after mirroring the bright part is on the RIGHT
    assert g[:, 19].mean() > 0.9 and g[:, 0].mean() < 0.1
    assert to_grid(img, mirror=False)[:, 0].mean() > 0.9


def test_color_map_hues_white_and_off():
    assert color_map(np.full((20, 20, 3), [1, 0, 0], np.float32))[0, 0] == 0                  # red
    assert abs(int(color_map(np.full((20, 20, 3), [0, 1, 0], np.float32))[0, 0]) - 60) <= 1   # green
    assert abs(int(color_map(np.full((20, 20, 3), [0, 0, 1], np.float32))[0, 0]) - 120) <= 1  # blue
    assert color_map(np.full((20, 20, 3), 0.8, np.float32))[0, 0] == WHITE                    # grey/white
    assert color_map(np.zeros((20, 20, 3), np.float32))[0, 0] == OFF                          # black


def test_thermal_orders_brightness_dark_to_white():
    gray = np.tile(np.linspace(0, 1, 20, dtype=np.float32), (20, 1))
    out = thermal_map(gray)
    row = list(out[0])
    assert row[0] == OFF and row[-1] == WHITE
    hues = [v for v in row if v not in (OFF, WHITE)]
    assert hues == sorted(hues, reverse=True) and hues[0] > 90 and hues[-1] < 20   # blue ... red
    assert (thermal_map(np.full((20, 20), 0.5, np.float32)) == OFF).all()          # flat scene: no noise


def test_silhouette_and_motion():
    rgb = np.full((20, 20, 3), 0.3, np.float32)
    bg = rgb.copy()
    rgb[5:10, 5:10] = [1, 0, 0]          # red block whose brightness happens to match the background
    assert abs(float(gray_of(rgb)[6, 6]) - 0.3) < 0.01
    out = silhouette_map(rgb, bg)
    assert (out[5:10, 5:10] == 0).all() and (out[:5] == OFF).all() and (out[:, 12:] == OFF).all()
    prev = np.full((20, 20), 0.2, np.float32)
    cur = prev.copy()
    cur[2:4, 2:4] = 0.9
    cur[10:12, 10:12] = 0.3
    m = motion_map(cur, prev)
    assert m[2, 2] < m[10, 10] and m[2, 2] != OFF and m[15, 15] == OFF     # big motion warmer than small


def test_distance():
    assert distance(5, 5) == 0 and distance(10, 13) == 3 and distance(2, 178) == 4   # hue wraps around
    assert distance(OFF, WHITE) == 90 and distance(OFF, 60) == 90 and distance(WHITE, 0) == 90


def test_mirror_budget_hysteresis_and_convergence():
    src = FakeSource(bgr((255, 255, 255)))
    src.frame[:, 80:] = 0                                   # half white, half black
    m = Mirror(source=src, mode="color", budget=79)
    changed = []
    for _ in range(8):
        m.step()
        changed.append(m.changed)
    assert max(changed) <= 79 and changed[0] == 79         # one packet's worth per step
    assert sum(changed) == 200 and changed[-1] == 0        # converged: half the grid is white
    assert sum(1 for c in m.frame() if c == WHITE) == 200
    before = list(m.frame())
    m.step()
    assert m.frame() == before                             # steady picture -> nothing re-sent
    # tiny noise below the hue threshold is ignored
    assert THRESHOLD > 3 and distance(60, 63) < THRESHOLD


def test_mirror_modes_keys_background_status_and_close():
    src = FakeSource(bgr((200, 40, 40)))
    m = Mirror(source=src, mode="thermal")
    assert m.status() == "waiting for camera..."
    m.step()
    assert "thermal" in m.status()
    m.key("right"); m.key("right")
    assert m.mode == "silhouette"
    m.step()
    assert m.background is not None
    m.key("space")
    assert m.background is None
    m.key("left"); m.key("left"); m.key("left")
    assert m.mode == "motion"
    for _ in range(4):
        m.step()
    f = m.frame()
    assert len(f) == 400 and all(P.validate_color_byte(c) is not None for c in f)
    m.close()
    assert src.closed


def test_no_camera_shows_error_frame_and_help(monkeypatch):
    import hellofairy.mirror as mir
    monkeypatch.setattr(mir, "CvSource", lambda i: (_ for _ in ()).throw(RuntimeError(mir.CAMERA_HELP)))
    m = Mirror()
    assert m.error and "Privacy" in m.status()
    assert m.frame() == mir.error_frame()
    m.step()                                                # must not crash


def test_demo_source_end_to_end_all_modes():
    m = Mirror(demo=True)
    for mode in ("thermal", "color", "silhouette", "motion"):
        m.mode_i = ("thermal", "color", "silhouette", "motion").index(mode)
        for _ in range(6):
            m.step()
        f = m.frame()
        assert len(f) == 400 and all(P.validate_color_byte(c) is not None for c in f)
    assert isinstance(DemoSource().read(), np.ndarray)
    m.close()
