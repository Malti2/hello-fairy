"""The lights drop the BLE link after a while; the tool must recover instead of crashing."""
import asyncio

import pytest
from bleak import BleakError

from hellofairy import ble, config
from hellofairy import protocol as P
from hellofairy.effects import ensure_draw_mode, send_changes, OFF

DISCOVERY = "Service Discovery has not been performed yet"


class World:
    """Fake radio: hands out FakeClients, records every delivered packet."""

    def __init__(self):
        self.clients = []
        self.delivered = []
        self.connect_failures = 0


class FakeDevice:
    address = "AAAA-BBBB"
    name = "Hello Fairy-1234"


def install(monkeypatch, tmp_path, world):
    monkeypatch.setenv("HELLOFAIRY_CONFIG", str(tmp_path / "c.json"))

    class FakeClient:
        def __init__(self, device, timeout=None):
            self.connected = False
            self.fail_next_write = None
            world.clients.append(self)

        @property
        def is_connected(self):
            return self.connected

        async def connect(self):
            if world.connect_failures:
                world.connect_failures -= 1
                raise BleakError("device not found")
            self.connected = True

        async def start_notify(self, uuid, cb):
            pass

        async def disconnect(self):
            self.connected = False

        async def write_gatt_char(self, uuid, data, response=False):
            if self.fail_next_write:
                err, self.fail_next_write = self.fail_next_write, None
                raise err
            if not self.connected:
                raise BleakError(DISCOVERY)         # exactly what the user saw
            world.delivered.append(bytes(data))

    class FakeScanner:
        @staticmethod
        async def find_device_by_address(addr, timeout=None):
            return FakeDevice()

    monkeypatch.setattr(ble, "BleakClient", FakeClient)
    monkeypatch.setattr(ble, "BleakScanner", FakeScanner)

    async def no_sleep(_):
        pass
    monkeypatch.setattr(ble.asyncio, "sleep", no_sleep)


def run(coro):
    return asyncio.run(coro)


def test_write_after_silent_disconnect_reconnects_and_delivers(monkeypatch, tmp_path):
    world = World()
    install(monkeypatch, tmp_path, world)

    async def go():
        f = ble.Fairy("AAAA-BBBB")
        await f.connect()
        f.screen_state = {i: OFF for i in range(400)}
        f.client.connected = False                   # the lights hung up
        await f.write(P.power_packet(True))
        return f
    f = run(go())
    assert world.delivered == [P.power_packet(True)]
    assert len(world.clients) == 2 and f.reconnects == 1
    assert f.screen_state is None                    # curtain must be re-initialised


def test_error_mid_write_is_retried_once_after_reconnect(monkeypatch, tmp_path):
    world = World()
    install(monkeypatch, tmp_path, world)

    async def go():
        f = ble.Fairy("AAAA-BBBB")
        await f.connect()
        f.client.fail_next_write = BleakError(DISCOVERY)   # link died exactly during the write
        await f.write(P.power_packet(False))
        return f
    f = run(go())
    assert world.delivered == [P.power_packet(False)] and f.reconnects == 1


def test_unrelated_errors_are_not_swallowed(monkeypatch, tmp_path):
    world = World()
    install(monkeypatch, tmp_path, world)

    async def go():
        f = ble.Fairy("AAAA-BBBB")
        await f.connect()
        f.client.fail_next_write = ValueError("bad packet")
        await f.write(b"\xaa")
    with pytest.raises(ValueError):
        run(go())


def test_reconnect_retries_then_gives_up_with_clear_message(monkeypatch, tmp_path):
    world = World()
    install(monkeypatch, tmp_path, world)

    async def go(failures):
        f = ble.Fairy("AAAA-BBBB")
        await f.connect()
        f.client.connected = False
        world.connect_failures = failures
        await f.write(P.power_packet(True))
        return f
    assert run(go(3)).reconnects == 1                # recovers on the 4th attempt
    world.delivered.clear()
    with pytest.raises(ConnectionError, match="could not reconnect"):
        run(go(99))


def test_draw_mode_is_reinitialised_after_reconnect(monkeypatch, tmp_path):
    world = World()
    install(monkeypatch, tmp_path, world)

    class Info:
        pass

    async def go():
        f = ble.Fairy("AAAA-BBBB")
        await f.connect()

        async def fake_require(force=False):
            return None
        async def fake_power(on):
            return None                              # the fake lights never send ACKs
        f.require_curtain = fake_require
        f.power = fake_power
        s1 = await ensure_draw_mode(f)
        n_before = len(world.delivered)
        f.client.connected = False
        await f.write(P.power_packet(True))          # reconnect happens here
        s2 = await ensure_draw_mode(f)
        return f, s1, s2, n_before
    f, s1, s2, n_before = run(go())
    assert s1 is not s2 and f.reconnects == 1
    assert P.d0_packet(0x03) in world.delivered[n_before:] and P.d0_packet(0x00) in world.delivered[n_before:]


def test_send_changes_stops_when_link_was_recreated_midway(monkeypatch, tmp_path):
    world = World()
    install(monkeypatch, tmp_path, world)

    async def go():
        f = ble.Fairy("AAAA-BBBB")
        await f.connect()
        state = {i: OFF for i in range(400)}
        f.screen_state = state
        calls = {"n": 0}
        real_write = f.write

        async def flaky_write(pkt, **kw):
            calls["n"] += 1
            if calls["n"] == 2:
                f.client.connected = False           # drop while sending packet 2
            await real_write(pkt, **kw)
        f.write = flaky_write
        ok = await send_changes(f, state, [60] * 400)
        return f, state, ok
    f, state, ok = run(go())
    assert ok is False and f.reconnects == 1
    assert sum(1 for v in state.values() if v == 60) == 79      # only the first, confirmed batch
