from datetime import datetime

import pytest

from hellofairy import protocol as P
from hellofairy.clock import (HOUR_COLOR, MIN_COLOR, SEC_COLOR, Clock, hand_angles, render_analog,
                              render_digital, time_color)


def at(h, m, s=0):
    return datetime(2026, 11, 7, h, m, s)   # a Saturday


def cells(f, color):
    return {(i % 20, i // 20) for i, c in enumerate(f) if c == color}


def test_hand_angles():
    assert hand_angles(at(3, 0, 0)) == (90, 0, 0)
    assert hand_angles(at(6, 30, 30))[0] == pytest.approx(195.25, abs=0.01)
    assert hand_angles(at(15, 0, 0))[0] == 90          # 24h -> 12h
    assert hand_angles(at(12, 15, 0))[1] == 90 and hand_angles(at(0, 0, 45))[2] == 270


def test_analog_three_oclock():
    f = render_analog(at(3, 0, 0))
    hour = cells(f, HOUR_COLOR)
    assert {(x, 10) for x in range(10, 14)} <= hour and all(y == 10 for _, y in hour)   # points right
    minute = cells(f, MIN_COLOR)
    assert (10, 4) in minute and all(x == 10 for x, _ in minute)                        # points up


def test_analog_six_and_nine_are_symmetric_to_twelve_and_three():
    down = cells(render_analog(at(6, 0, 0)), HOUR_COLOR)
    left = cells(render_analog(at(9, 0, 0)), HOUR_COLOR)
    assert all(x == 10 for x, _ in down) and max(y for _, y in down) >= 13
    assert all(y == 10 for _, y in left) and min(x for x, _ in left) <= 7


def test_hands_move_and_second_hand_steps():
    assert render_analog(at(3, 0, 0)) != render_analog(at(3, 0, 5))
    assert render_analog(at(3, 0, 0)) != render_analog(at(3, 1, 0))
    assert cells(render_analog(at(3, 0, 20)), SEC_COLOR)


def test_ticks_quarters_white_rest_blue():
    f = render_analog(at(1, 1, 1))
    for x, y in ((10, 0), (19, 10), (10, 19), (0, 10)):
        assert f[y * 20 + x] == 255
    assert sum(1 for c in f if c == 120) == 8


def test_digital_layout_and_colors():
    f = render_digital(at(12, 34, 0))
    assert time_color(12) == 60
    assert cells(f, 60)                                   # digits green in the afternoon
    assert cells(f, 255)                                  # colon visible on even seconds
    assert not cells(render_digital(at(12, 34, 1)), 255)  # blinks off on odd seconds
    assert sum(1 for x in range(20) if f[17 * 20 + x] == 90) == round(1 * 20 / 60)
    assert sum(1 for x in range(20) if render_digital(at(12, 34, 59))[17 * 20 + x] == 90) == 20


def test_weekday_dots():
    f = render_digital(at(8, 0, 0))                       # Saturday -> index 5
    dots = [f[3 * 20 + 3 + 2 * d] for d in range(7)]
    assert dots == [120] * 5 + [30, 120]


@pytest.mark.parametrize("hour", [0, 5, 9, 13, 20, 23])
@pytest.mark.parametrize("page", [0, 1])
def test_frames_valid(hour, page):
    c = Clock(now=lambda: at(hour, 59, 59))
    c.page = page
    f = c.frame()
    assert len(f) == 400 and all(P.validate_color_byte(v) is not None for v in f)


def test_page_switch_and_status():
    c = Clock(now=lambda: at(8, 5, 9))
    c.key("right")
    assert c.page == 1 and "digital" in c.status() and "08:05:09" in c.status()
    c.key("left")
    assert c.page == 0
    c.key("right"); c.reset()
    assert c.page == 0
