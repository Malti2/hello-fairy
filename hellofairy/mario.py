"""Mario platformer for the 20x20 curtain (camera follows you to the right, like the original).

Mario is 2 pixels tall (3 with a mushroom). Four generated levels (each ends with flagpole,
castle and fireworks), then a Bowser level, then the cycle repeats harder.
Keys: left/right walk, up/space jump (keeps your direction in the air), x fireball (fire flower).

Colours (hue byte): Mario 0 red (fire: white head) | ground/stairs/used block 15 orange |
? block 30 yellow | pipe 60 green | goomba 140 violet | koopa 90 cyan | shell 120 blue |
mushroom 165 magenta | fire flower 45 lime | fireball/pole/castle 255 white | Bowser 60 green |
Bowser flame 30 yellow | flag 0 red.
"""

from __future__ import annotations

import random
import time
from dataclasses import dataclass, field

from . import protocol as P
from .pong import text_frame
from .snake import text_frame as game_over_text

W, H = P.WIDTH, P.HEIGHT
GROUND_Y = 18           # first ground row; Mario stands on row 17
STAND = GROUND_Y - 1
BLOCK_ROW = 14          # ? blocks: a jump (rise 4) lets Mario stand on top of them (row 13)
JUMP_VY = (-2, -1, -1)  # then 0 at the apex, then gravity: total rise 4
CAM_TRIGGER = 9         # camera scrolls once Mario passes this screen column
MOVE_COOLDOWN = 2       # ticks between steps on the ground (max 5 columns per second)
AIR_COOLDOWN = 1        # in the air Mario covers 1 column per tick (a jump spans ~6 columns)

# tile ids
EMPTY, GROUND, PIPE, QBLOCK, USED, POLE, CASTLE, FLAG = range(8)
SOLID = {GROUND, PIPE, QBLOCK, USED}
TILE_COLOR = {GROUND: 15, PIPE: 60, QBLOCK: 30, USED: 15, POLE: 255, CASTLE: 255, FLAG: 0}

C_MARIO, C_FIRE_HEAD = 0, 255
C_GOOMBA, C_KOOPA, C_SHELL = 140, 90, 120
C_MUSHROOM, C_FLOWER, C_FIREBALL = 165, 45, 255
C_BOWSER, C_FLAME, C_BOSS_HIT, C_BOSS_HP = 60, 30, 255, 165


# ------------------------------------------------------------------ level generation
@dataclass
class Level:
    width: int
    cols: list                      # cols[x][y] -> tile id
    contents: dict = field(default_factory=dict)   # (x, y) -> 'mushroom' | 'flower' | 'coin'
    spawns: list = field(default_factory=list)     # (kind, x, y)
    pole_x: int = -1
    castle_x: int = -1
    boss: bool = False

    @property
    def cam_max(self) -> int:
        return max(0, self.width - W)


def _ground(width: int) -> list:
    return [[GROUND if y >= GROUND_Y else EMPTY for y in range(H)] for _ in range(width)]


def _place_qblocks(lvl: Level, x: int, n: int, rng, first: bool = False) -> int:
    for i in range(n):
        lvl.cols[x + i][BLOCK_ROW] = QBLOCK
        lvl.contents[(x + i, BLOCK_ROW)] = ("mushroom" if first and i == 0
                                            else rng.choices(["mushroom", "flower", "coin"], [4, 3, 3])[0])
    return x + n


def generate_level(num: int, cycle: int, rng: random.Random) -> Level:
    """num 1-4 = normal levels, 5 = Bowser.

    Rules: first 14 columns are safe and flat; every feature is followed by >= 4 columns of
    plain ground (so nothing is un-jumpable); pipes are 2 wide and 2-3 high (never enterable);
    pits are 2 wide (3 from difficulty 3), at most one per 14 columns; ? blocks sit 3 rows above
    the ground (jumpable platforms) in groups of 1-3 holding mushroom / fire flower / coin; the first one always holds
    a mushroom; koopas appear from difficulty 2; the end is stairs + flagpole + castle.
    """
    if num == 5:
        lvl = Level(W, _ground(W), boss=True)
        for x in (5, 6):
            lvl.cols[x][BLOCK_ROW] = QBLOCK
            lvl.contents[(x, BLOCK_ROW)] = "flower"
        lvl.spawns.append(("boss", 15, 15))
        return lvl
    diff = cycle * 4 + num
    length = min(150, 76 + 8 * diff)
    lvl = Level(length + 16, _ground(length + 16))
    x = _place_qblocks(lvl, 14, 1, rng, first=True) + 6
    last_pit_end = -99
    while x < length - 8:
        options = [("goomba", 3), ("qblock", 3), ("pipe", 3)]
        if diff >= 2:
            options.append(("koopa", 2))
        if x - last_pit_end >= 14:
            options.append(("pit", 2))
        kind = rng.choices([k for k, _ in options], [w for _, w in options])[0]
        if kind == "pipe":
            h = rng.choice((2, 3))
            for dx in (0, 1):
                for y in range(GROUND_Y - h, GROUND_Y):
                    lvl.cols[x + dx][y] = PIPE
            end = x + 2
        elif kind == "pit":
            w = rng.choice((2, 3)) if diff >= 3 else 2
            for dx in range(w):
                lvl.cols[x + dx][GROUND_Y] = lvl.cols[x + dx][GROUND_Y + 1] = EMPTY
            end = last_pit_end = x + w
        elif kind == "goomba":
            n = rng.randint(1, 1 + diff // 4)
            for i in range(n):
                lvl.spawns.append(("goomba", x + 3 * i, STAND))
            end = x + 3 * n
        elif kind == "koopa":
            lvl.spawns.append(("koopa", x, STAND))
            end = x + 1
        else:
            end = _place_qblocks(lvl, x, rng.randint(1, 3), rng)
        x = end + rng.randint(max(4, 8 - diff // 3), 9)
    for i in range(4):                                   # stairs
        for y in range(STAND - i, GROUND_Y):
            lvl.cols[length + i][y] = GROUND
    lvl.pole_x = length + 5
    for y in range(9, GROUND_Y):
        lvl.cols[lvl.pole_x][y] = POLE
    lvl.cols[lvl.pole_x - 1][9] = FLAG
    lvl.castle_x = length + 8
    for dx in range(5):
        for y in range(14, GROUND_Y):
            lvl.cols[lvl.castle_x + dx][y] = CASTLE
        if dx % 2 == 0:
            lvl.cols[lvl.castle_x + dx][13] = CASTLE
    for y in (16, 17):
        lvl.cols[lvl.castle_x + 2][y] = EMPTY            # door
    return lvl


# ------------------------------------------------------------------ entities
@dataclass
class Enemy:
    kind: str            # goomba | koopa | shell
    x: int
    y: int
    vx: int = -1
    timer: int = 0
    active: bool = False
    grace: int = 0


@dataclass
class Item:
    kind: str            # mushroom | flower
    x: int
    y: int
    vx: int = 1
    timer: int = 0


@dataclass
class Fireball:
    x: int
    y: int
    age: int = 0


@dataclass
class Flame:
    x: int
    y: int
    timer: int = 0


@dataclass
class Boss:
    x: int
    y: int
    hp: int
    dir: int = -1
    timer: int = 0
    flash: int = 0


# ------------------------------------------------------------------ the game
class Mario:
    space_key = True  # arcade: space = jump
    tick = 0.1
    hint = "left/right move · up/space jump · x fireball · p pause · q menu"

    def __init__(self, rng=None, clock=time.monotonic):
        self.rng = rng or random.Random()
        self.clock = clock
        self.reset()

    # -- setup -----------------------------------------------------------------------
    def reset(self) -> None:
        self.cycle, self.num, self.lives, self.score, self.power = 0, 1, 3, 0, 0
        self.over = False
        self.seeds: dict = {}
        self.banners: list = []
        self._banner_start = None
        self._load_level()

    @property
    def h(self) -> int:
        return 2 if self.power == 0 else 3   # small Mario is 2 pixels tall

    def _level_for(self) -> Level:
        seed = self.seeds.setdefault((self.cycle, self.num), self.rng.randrange(1 << 30))
        return generate_level(self.num, self.cycle, random.Random(seed))  # same layout on retry

    def _load_level(self, lvl: Level | None = None, banner: bool = True) -> None:
        self.lvl = lvl or self._level_for()
        self.cam = self.t = self.vy = self.invuln = self.cd = self.air_dir = 0
        self.jump_i = None
        self.hdir, self.hdir_age = 0, 99
        self.phase = "play"
        self.moved_down = False
        self.hidden = False
        self.enemies, self.items, self.fireballs, self.flames, self.bursts = [], [], [], [], []
        self.boss = None
        if self.lvl.boss:
            self.power = 2  # Bowser needs fireballs
        self.mx = 2 if self.lvl.boss else 3
        self.my = STAND - (self.h - 1)
        for kind, x, y in self.lvl.spawns:
            if kind == "boss":
                self.boss = Boss(x, y, min(12, 5 + 2 * self.cycle))
            else:
                self.enemies.append(Enemy(kind, x, y))
        if banner:
            label = "BOSS" if self.lvl.boss else f"{self.cycle + 1}-{self.num}"
            self.banners = [(text_frame(label, 30), 1.0)]
            self._banner_start = None

    def status(self) -> str:
        world = "BOSS" if self.lvl.boss else f"{self.cycle + 1}-{self.num}"
        extra = f"  bowser hp {self.boss.hp}" if self.boss else ""
        return (f"world {world}  score {self.score}  lives {self.lives}  "
                f"{('small', 'big', 'fire')[self.power]}{extra}" + ("  GAME OVER - r" if self.over else ""))

    # -- banners -----------------------------------------------------------------------
    def _banner(self):
        while self.banners:
            frame, secs = self.banners[0]
            if self._banner_start is None:
                self._banner_start = self.clock()
            if secs == float("inf") or self.clock() - self._banner_start < secs:
                return frame
            self.banners.pop(0)
            self._banner_start = None
        return None

    # -- world queries -----------------------------------------------------------------
    def _solid(self, x: int, y: int) -> bool:
        if x >= self.lvl.width:
            return True
        if x < 0 or y < 0 or y >= H:
            return False
        return self.lvl.cols[x][y] in SOLID

    def _collide(self, x: int, y_top: int, h: int) -> bool:
        return any(self._solid(x, y) for y in range(y_top, y_top + h))

    def _on_ground(self) -> bool:
        return self._solid(self.mx, self.my + self.h)

    def _hits(self, x: int, y: int, w: int = 1, h: int = 1) -> bool:
        return x <= self.mx < x + w and y < self.my + self.h and y + h > self.my

    # -- input -----------------------------------------------------------------------
    def key(self, name: str) -> None:
        if self.over or self.phase != "play" or self._banner() is not None:
            return
        if name in ("left", "right"):
            d = -1 if name == "left" else 1
            self.hdir, self.hdir_age = d, 0
            if not self._on_ground():
                self.air_dir = d
            if self.cd <= 0 and self._move_x(d):
                self.cd = MOVE_COOLDOWN if self._on_ground() else AIR_COOLDOWN
                self._follow_camera()
        elif name in ("up", "space"):
            if self._on_ground() and self.vy >= 0 and self.jump_i is None:
                self.jump_i = 0
                # terminals drop the held arrow when jump is pressed: keep recent direction
                self.air_dir = self.hdir if self.hdir_age <= 6 else 0
        elif name == "rotate" and self.power == 2 and len(self.fireballs) < 2:
            self.fireballs.append(Fireball(self.mx + 1, self.my + self.h - 1))

    # -- movement --------------------------------------------------------------------
    def _move_x(self, dx: int) -> bool:
        nx = self.mx + dx
        if not 0 <= nx - self.cam < W:
            return False
        if self._collide(nx, self.my, self.h):
            # step up a one-high ledge (stairs, small blocks) while walking
            if (self._on_ground() and not self._collide(nx, self.my - 1, self.h)
                    and not self._solid(self.mx, self.my - 1)):
                self.mx, self.my = nx, self.my - 1
                return True
            return False
        self.mx = nx
        return True

    def _mario_vertical(self) -> None:
        self.moved_down = False
        if self.jump_i is not None:
            self.vy = JUMP_VY[self.jump_i]
            self.jump_i += 1
            if self.jump_i >= len(JUMP_VY):
                self.jump_i = None
        d = 1 if self.vy > 0 else -1
        for _ in range(abs(self.vy)):
            ny = self.my + d
            if self._collide(self.mx, ny, self.h):
                if d < 0:
                    self._hit_block(self.mx, ny)
                self.vy, self.jump_i = 0, None
                break
            self.my = ny
            if d > 0:
                self.moved_down = True
        if self.jump_i is None:
            self.vy = min(2, self.vy + 1)
        if self.vy > 0 and self._on_ground():
            self.vy = 0
            self.air_dir = 0

    def _hit_block(self, x: int, y: int) -> None:
        if not 0 <= x < self.lvl.width or not 0 <= y < H or self.lvl.cols[x][y] != QBLOCK:
            return
        self.lvl.cols[x][y] = USED
        content = self.lvl.contents.pop((x, y), "coin")
        for e in list(self.enemies):                     # enemies standing on it get knocked off
            if (e.x, e.y) == (x, y - 1):
                self.enemies.remove(e)
                self.score += 100
        if content == "coin":
            self.score += 200
        elif not self._solid(x, y - 1):
            kind = "mushroom" if content == "mushroom" or self.power == 0 else "flower"
            self.items.append(Item(kind, x, y - 1))

    def _follow_camera(self) -> None:
        if not self.lvl.boss:
            target = min(self.lvl.cam_max, self.mx - CAM_TRIGGER)
            if target > self.cam:           # never scrolls back, like the original
                self.cam = target

    def _grow(self, to: int) -> None:
        if self.power == 0 and to >= 1:
            if self._solid(self.mx, self.my - 1):
                return
            self.my -= 1
        self.power = max(self.power, to)

    def _hurt(self) -> None:
        if self.invuln > 0 or self.phase != "play":
            return
        if self.power > 0:
            self.power = 0
            self.my += 1
            self.invuln = 20
        else:
            self._die()

    def _die(self) -> None:
        if self.phase == "play":
            self.phase, self.dead_t = "dead", 0

    # -- tick ----------------------------------------------------------------------------
    def step(self) -> None:
        if self.over or self._banner() is not None:
            return
        self.t += 1
        if self.phase == "play":
            self._play_tick()
        elif self.phase == "dead":
            self._dead_tick()
        else:
            self._clear_tick()

    def _play_tick(self) -> None:
        lvl = self.lvl
        self.invuln = max(0, self.invuln - 1)
        self.cd = max(0, self.cd - 1)
        self.hdir_age += 1
        if self.air_dir and not self._on_ground() and self.cd <= 0:
            if self._move_x(self.air_dir):
                self.cd = AIR_COOLDOWN
                self._follow_camera()
            else:
                self.air_dir = 0
        self._mario_vertical()
        self._update_enemies()
        self._update_items()
        self._update_fireballs()
        self._update_boss()
        self._contacts()
        if self.phase != "play":
            return
        if self.my >= H:
            return self._die()
        if not lvl.boss and self.mx >= lvl.pole_x:
            self._start_clear()

    def _update_enemies(self) -> None:
        for e in list(self.enemies):
            if not e.active:
                if e.x - self.cam <= W + 1:
                    e.active = True
                else:
                    continue
            if e.x < self.cam - 2:
                self.enemies.remove(e)
                continue
            e.grace = max(0, e.grace - 1)
            if not self._solid(e.x, e.y + 1):
                e.y += 1
                if e.y >= H:
                    self.enemies.remove(e)
                continue
            e.timer += 1
            period = 1 if (e.kind == "shell" and e.vx) else 4
            if e.vx and e.timer % period == 0:
                if self._solid(e.x + e.vx, e.y):
                    e.vx = -e.vx
                else:
                    e.x += e.vx
            if e.kind == "shell" and e.vx:               # sliding shell mows down others
                for o in list(self.enemies):
                    if o is not e and (o.x, o.y) == (e.x, e.y):
                        self.enemies.remove(o)
                        self.score += 200

    def _update_items(self) -> None:
        for it in list(self.items):
            if it.x < self.cam - 2:
                self.items.remove(it)
                continue
            if not self._solid(it.x, it.y + 1):
                it.y += 1
                if it.y >= H:
                    self.items.remove(it)
                continue
            it.timer += 1
            if it.kind == "mushroom" and it.timer % 4 == 0:
                if self._solid(it.x + it.vx, it.y):
                    it.vx = -it.vx
                else:
                    it.x += it.vx

    def _update_fireballs(self) -> None:
        for fb in list(self.fireballs):
            fb.age += 1
            gone = fb.age > 12
            for _ in range(2):
                nx = fb.x + 1
                if gone or nx >= self.cam + W or self._solid(nx, fb.y):
                    gone = True
                    break
                fb.x = nx
                if self._fireball_hit(fb):
                    gone = True
                    break
            if not gone and not self._solid(fb.x, fb.y + 1):
                fb.y += 1
                gone = fb.y >= H
            if gone:
                self.fireballs.remove(fb)

    def _fireball_hit(self, fb: Fireball) -> bool:
        for e in list(self.enemies):
            if (e.x, e.y) == (fb.x, fb.y):
                self.enemies.remove(e)
                self.score += 100
                return True
        b = self.boss
        if b and b.x <= fb.x < b.x + 3 and b.y <= fb.y < b.y + 3:
            b.hp -= 1
            b.flash = 3
            self.score += 200
            if b.hp <= 0:
                self.score += 3000
                self.boss = None
                self._start_clear()
            return True
        return False

    def _update_boss(self) -> None:
        b = self.boss
        if b:
            b.timer += 1
            b.flash = max(0, b.flash - 1)
            if b.timer % 6 == 0:
                if b.x <= 11:
                    b.dir = 1
                elif b.x >= 17:
                    b.dir = -1
                b.x += b.dir
            if b.timer % max(14, 30 - 3 * self.cycle) == 0:
                self.flames.append(Flame(b.x - 1, self.rng.choice((17, 15))))
        for f in list(self.flames):
            f.timer += 1
            if f.timer % 2 == 0:
                f.x -= 1
            if f.x < 0:
                self.flames.remove(f)

    def _contacts(self) -> None:
        feet = self.my + self.h - 1
        for e in list(self.enemies):
            if not self._hits(e.x, e.y):
                continue
            stomping = (self.moved_down or self.vy > 0) and feet <= e.y
            if e.kind == "shell":
                if e.grace:
                    continue
                if e.vx == 0:
                    e.vx, e.grace = (1 if self.mx <= e.x else -1), 4   # kick it away
                elif stomping:
                    e.vx, e.grace = 0, 4
                else:
                    self._hurt()
                    continue
                if stomping:
                    self.vy = -2
            elif stomping:
                self.score += 100 if e.kind == "goomba" else 200
                self.vy = -2
                if e.kind == "koopa":
                    e.kind, e.vx, e.grace = "shell", 0, 4
                else:
                    self.enemies.remove(e)
            else:
                self._hurt()
        for it in list(self.items):
            if self._hits(it.x, it.y):
                self.items.remove(it)
                self.score += 1000
                self._grow(1 if it.kind == "mushroom" else 2)
        if self.boss and self._hits(self.boss.x, self.boss.y, 3, 3):
            self._hurt()
        for f in self.flames:
            if self._hits(f.x, f.y):
                self._hurt()

    # -- death / level clear -------------------------------------------------------------
    def _dead_tick(self) -> None:
        self.dead_t += 1
        self.my += -1 if self.dead_t <= 3 else 1
        if self.dead_t >= 14:
            self.lives -= 1
            self.power = 0
            if self.lives <= 0:
                self.over = True
                self.banners, self._banner_start = [(game_over_text(), float("inf"))], None
            else:
                self._load_level()

    def _start_clear(self) -> None:
        self.phase, self.clear_t = "clear", 0
        self.score += 1000
        self.flames.clear()

    def _clear_tick(self) -> None:
        self.clear_t += 1
        if self.clear_t % 3 == 1:
            cx = (self.lvl.castle_x + 2 - self.cam) if not self.lvl.boss else W // 2
            sx = max(2, min(W - 3, cx + self.rng.randint(-4, 4)))
            self.bursts.append([sx, self.rng.randint(2, 8), 0, self.rng.randrange(0, 181)])
        for b in self.bursts:
            b[2] += 1
        self.bursts = [b for b in self.bursts if b[2] < 8]
        self._mario_vertical()
        if not self.lvl.boss and self.clear_t % 2 == 0 and not self.hidden:
            if self.mx >= self.lvl.castle_x + 2:
                self.hidden = True               # Mario walks into the castle
            else:
                self._move_x(1)
        if self.clear_t >= 40:
            self._next_level()

    def _next_level(self) -> None:
        if self.num == 4:
            self.num = 5                          # Bowser after four levels
        elif self.num == 5:
            self.cycle, self.num = self.cycle + 1, 1
        else:
            self.num += 1
        self._load_level()

    # -- rendering ---------------------------------------------------------------------
    def frame(self) -> list[int]:
        b = self._banner()
        if b is not None:
            return b
        f = [P.PIXEL_OFF] * (W * H)

        def put(sx: int, y: int, color: int) -> None:
            if 0 <= sx < W and 0 <= y < H:
                f[y * W + sx] = color

        lvl = self.lvl
        for sx in range(W):
            x = self.cam + sx
            if x < lvl.width:
                col = lvl.cols[x]
                for y in range(H):
                    if col[y]:
                        f[y * W + sx] = TILE_COLOR[col[y]]
        for it in self.items:
            put(it.x - self.cam, it.y, C_MUSHROOM if it.kind == "mushroom" else C_FLOWER)
        for e in self.enemies:
            put(e.x - self.cam, e.y, {"goomba": C_GOOMBA, "koopa": C_KOOPA, "shell": C_SHELL}[e.kind])
        if self.boss:
            bs = self.boss
            for dx in range(3):
                for dy in range(3):
                    put(bs.x + dx, bs.y + dy, C_BOSS_HIT if bs.flash else C_BOWSER)
        for fl in self.flames:
            put(fl.x, fl.y, C_FLAME)
        for fb in self.fireballs:
            put(fb.x - self.cam, fb.y, C_FIREBALL)
        if not self.hidden and not (self.invuln and self.t % 2):
            sx = self.mx - self.cam
            for i in range(self.h):
                head = i == 0 and self.power == 2
                put(sx, self.my + i, C_FIRE_HEAD if head else C_MARIO)
        for sx, sy, age, hue in self.bursts:
            r = age // 2 + 1
            for dx, dy in ((r, 0), (-r, 0), (0, r), (0, -r), (r, r), (-r, -r), (r, -r), (-r, r)):
                put(sx + dx, sy + dy, hue)
            if age < 2:
                put(sx, sy, P.PIXEL_WHITE)
        for i in range(self.lives):                      # HUD: lives, top-left
            put(1 + 2 * i, 0, C_MARIO)
        if self.boss:                                    # HUD: Bowser hit points, top-right
            for i in range(self.boss.hp):
                put(W - 1 - i, 1, C_BOSS_HP)
        return f
