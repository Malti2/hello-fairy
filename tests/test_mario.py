import random

import pytest

from hellofairy import protocol as P
from hellofairy.mario import (BLOCK_ROW, GROUND, GROUND_Y, PIPE, QBLOCK, STAND, USED, Boss,
                              Enemy, Item, Level, Mario, _ground, generate_level)


class Clock:
    t = 0.0

    def __call__(self):
        return self.t


def flat(width=60):
    return Level(width, _ground(width), pole_x=width - 4, castle_x=width - 2 if False else width - 8)


def game(lvl=None, power=0):
    g = Mario(rng=random.Random(1), clock=Clock())
    g.power = power
    g._load_level(lvl or flat(), banner=False)
    g.banners = []
    return g


def run(g, n):
    for _ in range(n):
        g.step()


# ---------------------------------------------------------------- generator rules
@pytest.mark.parametrize("cycle", [0, 1, 3])
@pytest.mark.parametrize("num", [1, 2, 3, 4])
def test_generator_rules(num, cycle):
    for seed in range(15):
        lvl = generate_level(num, cycle, random.Random(seed))
        cols = lvl.cols
        assert len(cols) == lvl.width and all(len(c) == 20 for c in cols)
        # safe flat start
        assert all(cols[x][GROUND_Y] == GROUND and not any(cols[x][:GROUND_Y]) for x in range(14))
        pits = [x for x in range(lvl.width) if cols[x][GROUND_Y] != GROUND]
        # pit width <= 3 and pits never touch the finish
        runs, cur = [], []
        for x in pits:
            if cur and x != cur[-1] + 1:
                runs.append(cur); cur = []
            cur.append(x)
        if cur:
            runs.append(cur)
        assert all(len(r) <= 3 for r in runs)
        assert all(r[-1] < lvl.pole_x - 8 for r in runs)
        # pipes: 2 wide, height 2-3, not enterable (solid), and >= 4 columns from any pit
        pipe_cols = [x for x in range(lvl.width) if cols[x][STAND] == PIPE]
        for x in pipe_cols:
            h = sum(1 for y in range(20) if cols[x][y] == PIPE)
            assert h in (2, 3)
            assert all(abs(x - p) >= 4 for p in pits)
        # ? blocks: only on the block row, content defined
        for (x, y), c in lvl.contents.items():
            assert y == BLOCK_ROW and cols[x][y] == QBLOCK and c in ("mushroom", "flower", "coin")
        assert lvl.contents[min(lvl.contents)] == "mushroom"
        # enemies stand on ground, never on top of / inside pits and not at the start
        for kind, x, y in lvl.spawns:
            assert kind in ("goomba", "koopa") and x >= 14 and y == STAND
            assert cols[x][GROUND_Y] == GROUND
            if num == 1 and cycle == 0:
                assert kind == "goomba"
        # finish: flagpole + castle exist
        assert cols[lvl.pole_x][9] and cols[lvl.castle_x][14]
        assert not cols[lvl.castle_x + 2][16] and not cols[lvl.castle_x + 2][17]  # door


def test_generator_deterministic_and_boss():
    a = generate_level(2, 0, random.Random(7))
    b = generate_level(2, 0, random.Random(7))
    assert a.cols == b.cols and a.spawns == b.spawns
    boss = generate_level(5, 0, random.Random(1))
    assert boss.boss and boss.cam_max == 0 and boss.spawns == [("boss", 15, 15)]


# ---------------------------------------------------------------- movement & scrolling
def test_jump_rises_four_and_lands():
    g = game()
    y0 = g.my
    g.key("up")
    ys = []
    for _ in range(10):
        g.step()
        ys.append(g.my)
    assert min(ys) == y0 - 4 and g.my == y0 and g.h == 2


def test_camera_only_follows_to_the_right():
    g = game()
    run(g, 20)
    assert g.cam == 0 and g.mx == 3                     # no automatic scrolling
    for _ in range(30):
        g.key("right")
        g.step()
    assert g.cam > 0 and g.mx - g.cam == 9              # scrolls once Mario passes column 9
    cam = g.cam
    for _ in range(60):
        g.key("left")
        g.step()
    assert g.cam == cam and g.mx == cam                 # can't scroll back or leave the screen


def test_walking_speed_is_limited():
    g = game()
    for _ in range(10):
        g.key("right")  # key repeat faster than the game tick
        g.key("right")
        g.key("right")
        g.step()
    assert g.mx - 3 <= 5


def test_pipe_blocks_walking():
    lvl = flat()
    for dx in (0, 1):
        for y in (16, 17):
            lvl.cols[8 + dx][y] = PIPE
    g = game(lvl)
    for _ in range(80):
        g.key("right")
        g.step()
    assert g.mx == 7 and g.phase == "play"


def test_jump_over_pipe_possible():
    lvl = flat()
    for dx in (0, 1):
        for y in (15, 16, 17):
            lvl.cols[8 + dx][y] = PIPE
    g = game(lvl)
    for _ in range(120):
        g.key("right")
        if g._on_ground() and g._solid(g.mx + 1, g.my + g.h - 1):
            g.key("up")
        g.step()
    assert g.mx > 10 and g.phase in ("play", "clear")


def test_step_up_one_high_ledge():
    lvl = flat()
    lvl.cols[8][17] = GROUND
    g = game(lvl)
    g.mx = 7
    assert g._move_x(1) and (g.mx, g.my) == (8, 15) and g.h == 2


def test_fall_in_pit_kills():
    lvl = flat()
    for x in (8, 9):
        lvl.cols[x][18] = lvl.cols[x][19] = 0
    g = game(lvl)
    g.mx = 8
    run(g, 5)
    assert g.phase == "dead"


# ---------------------------------------------------------------- enemies
def test_stomp_goomba():
    g = game()
    g.my, g.mx = 14, 6
    g.enemies.append(Enemy("goomba", 6, STAND, vx=0, active=True))
    g.vy = 1
    run(g, 4)
    assert not g.enemies and g.score >= 100 and g.phase == "play"


def test_side_contact_kills_small_and_shrinks_big():
    g = game()
    g.enemies.append(Enemy("goomba", g.mx, STAND, vx=0, active=True))
    g.step()
    assert g.phase == "dead"
    g = game(power=1)
    g.enemies.append(Enemy("goomba", g.mx, STAND, vx=0, active=True))
    g.step()
    assert g.phase == "play" and g.power == 0 and g.invuln > 0


def test_koopa_to_shell_kick_and_kill():
    g = game()
    g.my, g.mx = 14, 6
    g.enemies.append(Enemy("koopa", 6, STAND, vx=0, active=True))
    g.vy = 1
    run(g, 4)
    shell = g.enemies[0]
    assert shell.kind == "shell" and shell.vx == 0
    g.invuln = 0
    victim = Enemy("goomba", 15, STAND, vx=0, active=True)
    g.enemies.append(victim)
    shell.grace = 0
    g.my, g.vy = STAND - 1, 0
    g.mx, g.cd = shell.x - 1, 0  # walk into it from the left -> shell flies right
    g.key("right")
    g.step()
    assert shell.vx == 1
    run(g, 20)
    assert victim not in g.enemies and g.phase == "play"


def test_enemies_wait_offscreen_then_walk():
    g = game()
    e = Enemy("goomba", 40, STAND)
    g.enemies.append(e)
    run(g, 5)
    assert e.x == 40 and not e.active
    g.cam = 25
    g.mx = 26
    run(g, 8)
    assert e.active and e.x < 40


# ---------------------------------------------------------------- blocks, items, fireballs
def block_level():
    lvl = flat()
    lvl.cols[3][BLOCK_ROW] = QBLOCK
    lvl.contents[(3, BLOCK_ROW)] = "mushroom"
    return lvl


def test_hit_qblock_spawns_mushroom_and_grows():
    g = game(block_level())
    g.key("up")
    run(g, 3)
    assert g.lvl.cols[3][BLOCK_ROW] == USED
    assert any(i.kind == "mushroom" for i in g.items)
    for i in range(80):
        g.key("right" if i < 8 else "left")  # overshoot, then turn back for the mushroom
        g.step()
    assert g.power == 1 and g.h == 3


def test_flower_block_gives_mushroom_when_small_and_flower_when_big():
    lvl = flat()
    lvl.cols[3][BLOCK_ROW] = QBLOCK
    lvl.contents[(3, BLOCK_ROW)] = "flower"
    g = game(lvl)
    g._hit_block(3, BLOCK_ROW)
    assert g.items[0].kind == "mushroom"
    lvl = flat()
    lvl.cols[3][BLOCK_ROW] = QBLOCK
    lvl.contents[(3, BLOCK_ROW)] = "flower"
    g = game(lvl, power=1)
    g._hit_block(3, BLOCK_ROW)
    assert g.items[0].kind == "flower"
    g.items[0].x, g.items[0].y = g.mx, g.my
    g.step()
    assert g.power == 2


def test_fireball_needs_flower_and_kills_goomba():
    g = game()
    g.key("rotate")
    assert not g.fireballs
    g = game(power=2)
    g.enemies.append(Enemy("goomba", g.mx + 5, STAND, vx=0, active=True))
    g.key("rotate")
    assert len(g.fireballs) == 1
    run(g, 5)
    assert not g.enemies and not g.fireballs


# ---------------------------------------------------------------- finish, boss, lives
def test_flag_clear_fireworks_and_progression_to_boss():
    g = game()
    g.mx = g.lvl.pole_x
    g.step()
    assert g.phase == "clear"
    run(g, 5)
    assert g.bursts
    run(g, 40)
    assert (g.cycle, g.num) == (0, 2) and g.phase == "play"
    g.num = 4
    g._load_level(flat(), banner=False)
    g.banners = []
    g.mx = g.lvl.pole_x
    g.step()
    run(g, 45)
    assert g.num == 5 and g.lvl.boss and g.power == 2 and g.boss


def test_boss_defeat_starts_next_cycle():
    g = Mario(rng=random.Random(1), clock=Clock())
    g.num = 5
    g._load_level(banner=False)
    g.banners = []
    g.boss.hp = 2
    for n in range(2):
        g.fireballs.clear()
        g.fireballs.append(__import__("hellofairy.mario", fromlist=["Fireball"]).Fireball(g.boss.x - 1, g.boss.y + 1))
        g.step()
    assert g.boss is None and g.phase == "clear"
    run(g, 45)
    assert (g.cycle, g.num) == (1, 1) and not g.lvl.boss


def test_boss_flames_and_contact_hurt():
    g = Mario(rng=random.Random(1), clock=Clock())
    g.num = 5
    g._load_level(banner=False)
    g.banners = []
    run(g, 60)
    assert g.flames or g.phase != "play"  # Bowser breathes fire


def test_three_deaths_game_over_and_restart():
    g = game()
    for _ in range(3):
        g.phase = "play"
        g._die()
        run(g, 20)
        g.banners = []
    assert g.over and g.lives == 0
    g.reset()
    assert not g.over and g.lives == 3 and g.score == 0


def test_same_layout_after_death():
    g = Mario(rng=random.Random(4), clock=Clock())
    first = [c[:] for c in g.lvl.cols]
    g._die()
    run(g, 20)
    assert g.lvl.cols == first


# ---------------------------------------------------------------- rendering
def test_frames_valid_in_every_phase():
    g = Mario(rng=random.Random(2), clock=Clock())
    for phase in ("play", "dead", "clear"):
        g.banners = []
        g.phase = phase
        g.bursts = [[5, 5, 1, 30]]
        f = g.frame()
        assert len(f) == 400 and all(P.validate_color_byte(c) is not None for c in f)
    g.num = 5
    g._load_level(banner=False)
    g.banners = []
    f = g.frame()
    assert 60 in f and 165 in f  # bowser + hp bar


def test_distinct_colours_for_every_element():
    g = game(power=2)
    g.lvl.cols[5][BLOCK_ROW] = QBLOCK
    for dx in (0, 1):
        for y in (16, 17):
            g.lvl.cols[10 + dx][y] = PIPE
    g.enemies += [Enemy("goomba", 12, STAND), Enemy("koopa", 13, STAND), Enemy("shell", 14, STAND)]
    g.items += [Item("mushroom", 15, STAND), Item("flower", 16, STAND)]
    f = g.frame()
    colours = set(f) - {P.PIXEL_OFF}
    assert {0, 15, 30, 60, 90, 120, 140, 165, 45, 255} <= colours
