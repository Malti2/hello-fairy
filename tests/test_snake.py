import random
from hellofairy import protocol as P
from hellofairy.snake import Game


def test_move_and_wall_death():
    g = Game(rng=random.Random(1))
    head = g.snake[0]
    g.step()
    assert g.snake[0] == (head[0] + 1, head[1]) and len(g.snake) == 3
    for _ in range(30):
        g.step()
    assert not g.alive


def test_no_reverse_and_eat():
    g = Game(rng=random.Random(1))
    g.turn("left")
    g.step()
    assert g.dir == "right"
    hx, hy = g.snake[0]
    g.food = (hx + 1, hy)
    g.step()
    assert g.score == 1 and len(g.snake) == 4 and g.food not in g.snake


def test_self_collision():
    g = Game(rng=random.Random(1))
    g.snake.extend([(7, 10), (7, 11)])  # length 5
    g.food = (0, 0)
    for d in ("down", "left", "up"):
        g.turn(d); g.step()
    assert not g.alive


def test_delta_packet_single_pixel_matches_app_capture():
    assert P.delta_packets({226: 0})[0].hex() == "aada040100e2006b"


def test_white_border_and_inner_field():
    g = Game(rng=random.Random(1))
    f = g.frame()
    assert (g.w, g.h) == (18, 18)
    ring = [f[i] for i in range(20)] + [f[380 + i] for i in range(20)] + [f[i * 20] for i in range(20)] + [f[i * 20 + 19] for i in range(20)]
    assert set(ring) == {P.PIXEL_WHITE}
    assert all(c != P.PIXEL_WHITE for y in range(1, 19) for c in f[y * 20 + 1 : y * 20 + 19])


def test_game_over_animation():
    from hellofairy.snake import game_over_frames
    g = Game(rng=random.Random(1))
    for _ in range(30):
        g.step()
    assert not g.alive
    seq = game_over_frames(g)
    assert all(len(f) == 400 for f, _ in seq)
    from hellofairy.snake import text_frame
    assert seq[-1][0] == text_frame()
    assert all(f[0] == P.PIXEL_WHITE and f[399] == P.PIXEL_WHITE for f, _ in seq)  # border stays
    assert 3 < sum(d for _, d in seq) < 5


def test_text_frame_fits_inside_border():
    from hellofairy.snake import text_frame
    f = text_frame()
    inner = [f[y * 20 + x] for y in range(1, 19) for x in range(1, 19)]
    assert inner.count(0) > 30 and set(inner) <= {0, P.PIXEL_OFF}
    assert all(f[i] == P.PIXEL_WHITE for i in range(20))
