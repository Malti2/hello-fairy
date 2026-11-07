import asyncio

from hellofairy import protocol as P
from hellofairy.effects import OFF, tv_off_frames, play_frames
from hellofairy.menu import Menu


def lit_rows(f):
    return sorted({i // 20 for i, c in enumerate(f) if c != OFF})


def lit_cols(f):
    return sorted({i % 20 for i, c in enumerate(f) if c != OFF})


def source():
    return Menu().frame()


def test_all_frames_valid_and_ends_dark():
    seq = tv_off_frames(source())
    assert all(len(f) == 400 and all(P.validate_color_byte(c) is not None for c in f) for f, _ in seq)
    assert seq[0][0] == source()
    assert all(c == OFF for c in seq[-1][0])
    assert 1.0 < sum(d for _, d in seq) < 2.5


def test_picture_collapses_vertically_towards_the_centre():
    seq = tv_off_frames(source())
    spans = [(r[0], r[-1]) for f, _ in seq[1:9] for r in [lit_rows(f)]]
    heights = [b - a for a, b in spans]
    assert heights == sorted(heights, reverse=True) and heights[-1] <= 1
    assert all(a >= b_prev for (a, _), (b_prev, _) in zip(spans[1:], spans[:-1]))   # top edge moves down
    assert all(abs((a + b) / 2 - 9.5) <= 1 for a, b in spans)                        # always centred


def test_line_then_dot_shrink_towards_the_centre_columns():
    seq = tv_off_frames(source())
    line = [f for f, _ in seq[9:16]]
    widths = [len(lit_cols(f)) for f in line]
    assert widths == [20, 16, 12, 8, 6, 4, 2]
    assert all(lit_rows(f) == [9, 10] and set(f) - {OFF} == {255} for f in line)
    assert all(abs(sum(lit_cols(f)) / len(lit_cols(f)) - 9.5) < 0.01 for f in line)  # symmetric
    dot = seq[16][0]
    assert lit_cols(dot) == [9, 10] and lit_rows(dot) == [9, 10]


def test_play_frames_sends_only_changes_and_updates_state():
    class Fake:
        def __init__(self):
            self.packets = []

        async def write(self, pkt, **kw):
            self.packets.append(pkt)

    f, state = Fake(), {i: OFF for i in range(400)}
    seq = [([OFF] * 400, 0.0), ([5] + [OFF] * 399, 0.0), ([5] + [OFF] * 399, 0.0)]
    asyncio.run(play_frames(f, seq, state))
    assert len(f.packets) == 1 and f.packets[0][1] == 0xDA        # only the one changed pixel
    assert state[0] == 5 or state[P.pixel_index(0, 0)] == 5


from hellofairy.effects import (ensure_draw_mode, frame_from_state, send_changes, transition_frames,
                                tv_on_frames)


def test_tv_on_is_tv_off_reversed():
    f = source()
    on, off = tv_on_frames(f), tv_off_frames(f)
    assert [x for x, _ in on] == [x for x, _ in reversed(off)]
    assert all(c == OFF for c in on[0][0]) and on[-1][0] == f


def test_transition_closes_old_towards_centre_then_opens_new():
    old, new = [60] * 400, [120] * 400
    seq = transition_frames(old, new)
    assert seq[0][0] == old and seq[-1][0] == new                 # starts on old, ends on new
    sizes = [len(lit_cols(f)) for f, _ in seq]
    assert sizes == [20, 16, 12, 8, 6, 4, 2, 4, 6, 8, 12, 16, 20]
    mid = seq[3][0]                                               # 8x8 window, white frame
    assert lit_rows(mid) == list(range(6, 14)) and mid[6 * 20 + 6] == 255 and mid[9 * 20 + 9] == 60
    assert all(abs(sum(lit_cols(f)) / len(lit_cols(f)) - 9.5) < 0.01 for f, _ in seq)
    assert 0.4 < sum(d for _, d in seq) < 0.8


class Curtain:
    def __init__(self):
        self.packets = []

    async def write(self, pkt, **kw):
        self.packets.append(pkt)

    async def require_curtain(self, force=False):
        pass

    async def power(self, on):
        pass


def test_draw_mode_is_prepared_once_and_state_is_shared():
    async def go():
        c = Curtain()
        s1 = await ensure_draw_mode(c)
        n = len(c.packets)
        s2 = await ensure_draw_mode(c)
        return c, s1, s2, n
    c, s1, s2, n = asyncio.run(go())
    assert s1 is s2 and len(c.packets) == n == 2                  # D0 clear + D0 draw mode, once


def test_send_changes_updates_state_per_batch_and_roundtrips():
    async def go():
        c = Curtain()
        state = await ensure_draw_mode(c)
        frame = [i % 181 for i in range(400)]
        n1 = await send_changes(c, state, frame)
        before = len(c.packets)
        n2 = await send_changes(c, state, frame)                  # nothing changed -> nothing sent
        return c, state, frame, n1, n2, before
    c, state, frame, n1, n2, before = asyncio.run(go())
    assert n1 and not n2 and len(c.packets) == before
    assert frame_from_state(state) == frame
