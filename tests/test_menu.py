from hellofairy import protocol as P
from hellofairy.menu import ICONS, ITEMS, Menu


def test_navigation_wraps_and_enter_selects():
    m = Menu()
    m.key("up")
    assert m.items[m.index][0] == "quit"
    m.key("down"); m.key("down")
    assert m.items[m.index][0] == "pong"
    m.key("enter")
    assert m.done and m.choice == "pong"
    m.reset()
    assert not m.done and m.choice is None


def test_frames_valid_for_every_item():
    m = Menu()
    seen = []
    for _ in ITEMS:
        f = m.frame()
        assert len(f) == 400 and all(P.validate_color_byte(c) is not None for c in f)
        assert f[0] == P.PIXEL_WHITE
        seen.append(tuple(f))
        m.key("down")
    assert len(set(seen)) == len(ITEMS)  # each item looks different


def test_icons_fit_inside_border():
    assert all(len(set(map(len, rows))) == 1 and len(rows[0]) <= 18 and len(rows) <= 12
               for rows in ICONS.values())
