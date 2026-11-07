import random

from hellofairy import protocol as P
from hellofairy.tetris import COLS, ROWS, Tetris, rotated


class Clock:
    t = 0.0

    def __call__(self):
        return self.t


def make():
    clk = Clock()
    return Tetris(rng=random.Random(5), clock=clk), clk


def test_rotation_shapes():
    assert sorted(rotated("T", 1)) == [(1, 0), (1, 1), (1, 2), (2, 1)]
    assert sorted(rotated("O", 1)) == sorted(rotated("O", 0))
    assert sorted(rotated("I", 1)) == [(2, 0), (2, 1), (2, 2), (2, 3)]
    assert rotated("L", 4) == rotated("L", 0)


def test_bag_gives_all_seven_pieces():
    g, _ = make()
    seen = {g.kind, g.next_kind}
    for _ in range(6):
        g._spawn()
        seen.add(g.kind)
    assert len(seen) == 7


def test_move_walls_and_rotate_kick():
    g, _ = make()
    for _ in range(20):
        g.key("left")
    assert min(x for x, _ in g._cells(g.kind, g.rot, g.x, g.y)) == 0
    g.kind, g.rot, g.x, g.y = "I", 0, 0, 0
    g.key("up")  # vertical I at the left wall needs a kick to fit
    assert g.rot == 1 and min(x for x, _ in g._cells("I", 1, g.x, g.y)) >= 0


def test_hard_drop_locks_and_scores():
    g, _ = make()
    g.kind, g.rot, g.x, g.y = "O", 0, 4, 0
    g.key("space")
    assert g.board[ROWS - 1][4] is not None and g.board[ROWS - 2][5] is not None
    assert g.score == 2 * (ROWS - 2)


def test_line_clear():
    g, _ = make()
    for c in range(COLS - 2):
        g.board[ROWS - 1][c] = 60
    g.kind, g.rot, g.x, g.y = "O", 0, COLS - 2, 0
    g.key("space")
    assert g.lines == 1 and all(v is None for v in g.board[ROWS - 1][: COLS - 2])
    assert g.board[ROWS - 1][COLS - 1] is not None  # upper half of the O fell down
    assert g.score >= 100


def test_game_over_and_banner_persists():
    g, clk = make()
    for _ in range(100):
        g.key("space")
        if g.over:
            break
    assert g.over
    clk.t += 100
    assert g._banner() is not None and len(g.frame()) == 400


def test_frames_valid_and_layout():
    g, _ = make()
    f = g.frame()
    assert len(f) == 400 and all(P.validate_color_byte(c) is not None for c in f)
    assert f[0] == f[399] == P.PIXEL_WHITE
    assert all(f[y * 20 + 11] == P.PIXEL_WHITE for y in range(20))  # divider
    assert any(c not in (P.PIXEL_OFF, P.PIXEL_WHITE) for c in f[20 * 2 + 12 : 20 * 2 + 19])  # next piece shown


def test_gravity_speeds_up():
    g, _ = make()
    t0 = g.tick
    g.lines = 30
    assert g.tick < t0 and g.level == 4
