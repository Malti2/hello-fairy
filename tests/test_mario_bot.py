"""A simple bot walks generated levels: proves obstacles (pipes/pits) are beatable."""
import random

import pytest

from hellofairy.mario import GROUND_Y, Mario, generate_level


class Clock:
    t = 0.0

    def __call__(self):
        return self.t


def play_level(num, cycle, seed, enemies=True, max_ticks=4000):
    g = Mario(rng=random.Random(seed), clock=Clock())
    g.cycle, g.num = cycle, num
    lvl = generate_level(num, cycle, random.Random(seed))
    if not enemies:
        lvl.spawns = []
    g._load_level(lvl, banner=False)
    g.banners = []
    for _ in range(max_ticks):
        if g.phase == "clear":
            return "cleared"
        if g.phase != "play":
            return "dead"
        feet = g.my + g.h - 1
        wall = any(g._solid(g.mx + k, feet) for k in (1, 2))
        pit = any(not g._solid(g.mx + k, GROUND_Y) and g.mx + k < g.lvl.width for k in (1, 2))
        foe = any(e.active and e.y == feet and 0 < e.x - g.mx <= 3 for e in g.enemies)
        g.key("right")
        if g._on_ground() and (wall or pit or foe):
            g.key("up")
        g.step()
    return "timeout"


@pytest.mark.parametrize("cycle", [0, 1, 2])
@pytest.mark.parametrize("num", [1, 2, 3, 4])
def test_obstacle_only_levels_always_beatable(num, cycle):
    for seed in range(12):
        assert play_level(num, cycle, seed, enemies=False) == "cleared", (num, cycle, seed)


def test_levels_with_enemies_mostly_beatable_by_dumb_bot():
    wins = sum(play_level(n, 0, s) == "cleared" for n in (1, 2) for s in range(20))
    assert wins >= 28, wins  # of 40
