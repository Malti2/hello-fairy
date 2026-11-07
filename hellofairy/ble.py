"""BLE transport (bleak / CoreBluetooth on macOS)."""

from __future__ import annotations

import asyncio
import sys

from bleak import BleakClient, BleakScanner

from . import config
from . import protocol as P


def load_default() -> str | None:
    return config.load().get("address")


def save_default(address: str) -> None:
    config.update(address=address)


async def scan(timeout: float = 6.0, show_all: bool = False):
    """Return [(device, rssi, name)] of Hello Fairy devices (or all devices)."""
    found = await BleakScanner.discover(timeout=timeout, return_adv=True)
    out = []
    for dev, adv in found.values():
        name = dev.name or adv.local_name or ""
        if show_all or name.lower().startswith(P.NAME_PREFIX.lower()) or P.SERVICE_UUID in (adv.service_uuids or []):
            out.append((dev, adv.rssi, name))
    return sorted(out, key=lambda t: -t[1])


class Fairy:
    def __init__(self, address: str | None = None, *, log=lambda m: None):
        self.address = address or load_default()
        self.log = log
        self.client: BleakClient | None = None
        self.info: dict | None = None
        self._status: asyncio.Future | None = None
        self._info: asyncio.Future | None = None
        self._ack: dict[int, asyncio.Event] = {}
        # Screen state shared by the apps (see effects.ensure_draw_mode); None = curtain must be
        # re-initialised. `reconnects` counts dropped links we recovered from.
        self.screen_state: dict | None = None
        self.reconnects = 0
        self._reconnect_lock = asyncio.Lock()

    async def __aenter__(self):
        await self.connect()
        return self

    async def __aexit__(self, *exc):
        await self.disconnect()

    async def connect(self, scan_timeout: float = 8.0):
        await self._open(scan_timeout)

    async def _open(self, scan_timeout: float) -> None:
        device = None
        if self.address:
            self.log(f"Looking for {self.address} ...")
            device = await BleakScanner.find_device_by_address(self.address, timeout=scan_timeout)
        if device is None:
            self.log("Scanning for Hello Fairy devices ...")
            found = await scan(scan_timeout)
            if not found:
                raise ConnectionError("No Hello Fairy device found. Power it on and stay close; "
                                      "make sure the phone app is not connected.")
            device = found[0][0]
            self.log(f"Using {found[0][2]} ({device.address})")
        client = BleakClient(device, timeout=15)
        await client.connect()
        try:
            await client.start_notify(P.NOTIFY_UUID, self._on_notify)
        except Exception:
            await client.disconnect()
            raise
        self.client = client
        if device.address != load_default():
            save_default(device.address)
        self.address = device.address

    @property
    def connected(self) -> bool:
        return bool(self.client and self.client.is_connected)

    async def _drop(self) -> None:
        """Forget a dead link (best effort to close it)."""
        client, self.client = self.client, None
        if client is not None:
            try:
                await asyncio.wait_for(client.disconnect(), 3)
            except Exception:
                pass

    async def ensure_connected(self, attempts: int = 5) -> None:
        """Reconnect if the lights dropped the link. The curtain then needs re-initialising,
        so the shared screen state is invalidated (apps notice via `reconnects`)."""
        if self.connected:
            return
        async with self._reconnect_lock:
            if self.connected:
                return
            await self._drop()
            last: Exception | None = None
            for attempt in range(1, attempts + 1):
                try:
                    await self._open(scan_timeout=4.0 if attempt == 1 else 6.0)
                    self.reconnects += 1
                    self.screen_state = None
                    self.info = None
                    self.log(f"reconnected (#{self.reconnects})")
                    return
                except Exception as err:
                    last = err
                    await asyncio.sleep(min(2.0, 0.5 * attempt))
            raise ConnectionError(f"lost the connection to the lights and could not reconnect: {last}")

    async def disconnect(self):
        if self.client and self.client.is_connected:
            try:
                await self.client.disconnect()
            except Exception:
                pass

    # -- notifications -------------------------------------------------------------
    def _on_notify(self, _sender, data: bytearray):
        data = bytes(data)
        ack = P.is_ack(data)
        if ack is not None:
            ev = self._ack.get(ack)
            if ev:
                ev.set()
            return
        if (st := P.decode_status(data)) and self._status and not self._status.done():
            self._status.set_result(st)
        elif (inf := P.decode_device_info(data)) and self._info and not self._info.done():
            self._info.set_result(inf)

    # -- raw io --------------------------------------------------------------------
    async def write(self, packet: bytes, *, ack: bool = False, timeout: float = 5.0):
        ev = None
        for attempt in (1, 2):
            await self.ensure_connected()
            if ack:
                ev = self._ack[packet[1]] = asyncio.Event()
            try:
                await self.client.write_gatt_char(P.COMMAND_UUID, packet, response=False)
                break
            except Exception as err:
                text = str(err)
                dropped = (not self.connected or "Service Discovery" in text
                           or "not connected" in text.lower())
                if attempt == 2 or not dropped:
                    raise
                await self._drop()          # link died under us: reconnect and send once more
        if ev:
            try:
                await asyncio.wait_for(ev.wait(), timeout)
            except asyncio.TimeoutError:
                print(f"warning: no ACK for 0x{packet[1]:02x}", file=sys.stderr)

    async def get_info(self, timeout: float = 5.0) -> dict | None:
        self._info = asyncio.get_running_loop().create_future()
        await self.write(P.info_request())
        try:
            self.info = await asyncio.wait_for(self._info, timeout)
        except asyncio.TimeoutError:
            self.info = None
        return self.info

    async def get_status(self, timeout: float = 4.0) -> dict | None:
        self._status = asyncio.get_running_loop().create_future()
        await self.write(P.status_request())
        try:
            return await asyncio.wait_for(self._status, timeout)
        except asyncio.TimeoutError:
            return None

    # -- light commands ------------------------------------------------------------
    async def power(self, on: bool):
        await self.write(P.power_packet(on), ack=True)

    async def color(self, h: int, s: int, v: int):
        await self.power(True)
        await asyncio.sleep(0.1)
        await self.write(P.color_packet(h, s, v), ack=True)

    async def preset(self, n: int, brightness: int = 50):
        await self.power(True)
        await asyncio.sleep(0.1)
        await self.write(P.preset_packet(n, brightness), ack=True)

    async def brightness(self, pct: int):
        st = await self.get_status()
        if st and st["mode"] == 2:
            await self.write(P.preset_packet(st["preset"], pct), ack=True)
        elif st and st["mode"] == 1:
            await self.write(P.color_packet(st["hue"], int(st["saturation"]), pct), ack=True)
        else:
            await self.write(P.color_packet(0, 0, pct), ack=True)

    # -- pixel commands ------------------------------------------------------------
    def check_capacity(self, force: bool = False):
        assert self.client
        try:
            mtu = self.client.mtu_size
            char = self.client.services.get_characteristic(P.COMMAND_UUID)
            cap = char.max_write_without_response_size if char else 0
        except Exception:
            mtu, cap = None, 0
        self.log(f"MTU={mtu}, max write={cap}")
        if cap < P.DA_PACKET_BYTES and not force:
            raise RuntimeError(
                f"BLE write capacity {cap} < {P.DA_PACKET_BYTES} bytes: image upload would be "
                "dropped by the lights. Retry (reconnect) or use --force to try anyway.")

    async def require_curtain(self, force: bool = False):
        info = await self.get_info()
        if info is None:
            if force:
                return
            raise RuntimeError("Could not read device info. Use --force to try anyway.")
        self.log(f"Device: {info}")
        if (info["led_count"], info["columns"], info["rows"], info["diy_type"]) != (400, 20, 20, 3) \
                and not force:
            raise RuntimeError(
                f"Image upload only supports the 400-LED 20x20 curtain; this device reports {info}. "
                "Use --force to try anyway.")

    async def play_sequence(self, seq, *, force=False, progress=None):
        await self.require_curtain(force)
        self.check_capacity(force)
        await self.power(True)
        await asyncio.sleep(0.1)
        for i, (label, packet, delay) in enumerate(seq, 1):
            if progress:
                progress(i, len(seq), label)
            await self.write(packet)
            await asyncio.sleep(delay)

    async def send_image(self, frame, **kw):
        await self.play_sequence(P.single_image_sequence(frame), **kw)

    async def send_animation(self, frames, **kw):
        await self.play_sequence(P.two_picture_sequence(frames), **kw)

    async def playback(self, kind, movement, speed, brightness):
        for pkt in P.playback_packets(kind, movement, speed, brightness):
            await self.write(pkt)
            await asyncio.sleep(0.1)
