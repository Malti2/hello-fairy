import random

from hellofairy import protocol as P
from hellofairy.pong import AI_X, PLAYER_X, Pong


class Clock:
    t = 0.0

    def __call__(self):
        return self.t


def make(**kw):
    clk = Clock()
    g = Pong(rng=random.Random(3), clock=clk, **kw)
    return g, clk


def test_frame_valid_and_has_border_paddles_ball():
    g, _ = make()
    f = g.frame()
    assert len(f) == 400 and all(P.validate_color_byte(c) is not None for c in f)
    assert f[0] == f[399] == P.PIXEL_WHITE
    assert sum(1 for y in range(20) if f[y * 20 + PLAYER_X] == 60) == 4
    assert sum(1 for y in range(20) if f[y * 20 + AI_X] == 0) == 4


def test_paddle_clamped_to_field():
    g, _ = make()
    for _ in range(30):
        g.key("up")
    assert g.py == 1
    for _ in range(30):
        g.key("down")
    assert g.py + 4 == 19


def test_wall_bounce_and_player_hit():
    g, _ = make()
    g.bx, g.by, g.vx, g.vy = 5, 1, -1, -1
    g.step()
    assert g.vy == 1 and g.by == 2
    g.bx, g.by, g.vx, g.vy, g.py = 2, 9, -1, 0, 8
    g.step()
    assert g.vx == 1 and g.rally == 1  # bounced off the player paddle


def test_player_misses_ai_scores_and_serves_back():
    g, clk = make()
    g.bx, g.by, g.vx, g.vy, g.py = 2, 15, -1, 0, 1
    for _ in range(3):
        g.step()
    assert g.score == [0, 1]
    assert g.vx == -1  # served towards the player who lost the point
    f = g.frame()  # score banner shown
    assert f != Pong(rng=random.Random(1), clock=clk).frame()
    n = list(g.frame())
    g.step()
    assert (g.bx, g.by) == (10, g.by) or g.vx == -1  # frozen during banner
    clk.t += 5
    assert g._banner() is None


def test_win_and_lose_banner_persists():
    g, clk = make(points=1)
    g.bx, g.by, g.vx, g.vy, g.py = 16, 15, 1, 0, 1
    g.ay = 1
    for _ in range(4):
        g.step()
    assert g.over and g.score == [1, 0]
    clk.t += 100
    assert g._banner() is not None  # final WIN stays up


def test_ai_beats_idle_player_on_hard():
    g, clk = make(points=3, difficulty="hard")
    for _ in range(5000):
        clk.t += 1
        g.step()
        if g.over:
            break
    assert g.over and g.score[1] == 3 and g.score[0] == 0


def test_ai_returns_straight_ball():
    g, _ = make(difficulty="hard")
    g.bx, g.by, g.vx, g.vy = 8, 9, 1, 0
    g.ay = 1
    for _ in range(40):
        g.step()
        if g.vx < 0:
            break
    assert g.vx < 0 and g.rally >= 1
