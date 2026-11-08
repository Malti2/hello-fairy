# Hello Fairy – terminal control and games for Bluetooth LED curtains

A command-line tool for **Hello Fairy** Bluetooth LED lights, including image upload and real-time apps for the
**20×20 pixel curtain** (400 LEDs). It talks to the lights directly over BLE – no Home Assistant needed – and
comes with a game menu (Snake, Pong, Tetris, Mario), a webcam mirror, a clock and a weather display.

The Bluetooth protocol knowledge comes from [nzrutman/hello_fairy_ble](https://github.com/nzrutman/hello_fairy_ble),
which reverse-engineered it for Home Assistant. This project is an independent implementation built on that work.

## Contents

- [Requirements](#requirements)
- [Install](#install)
- [Basic control](#basic-control)
- [Apps and games](#apps-and-games)
- [Hardware limits](#hardware-limits)
- [Troubleshooting](#troubleshooting)
- [Development](#development)

## Requirements

- Hello Fairy BLE lights (the pixel features need the 400-LED, 20×20 curtain; plain light strings support the
  basic commands only).
- Python 3.10+. Developed on macOS; the Bluetooth part (`bleak`) is cross-platform, but the keyboard handling of
  the apps uses `termios`, so Windows is not supported for the apps.
- macOS asks for **Bluetooth** access for your terminal on first use (System Settings → Privacy & Security →
  Bluetooth). The Hello Fairy phone app must not be connected at the same time.

## Install

```bash
python3 -m venv .venv
.venv/bin/pip install -e .            # core: Bluetooth control, image upload, games, clock, weather
.venv/bin/pip install -e '.[camera]'  # + webcam mirror (OpenCV, NumPy)
source .venv/bin/activate
```

## Basic control

```bash
fairy scan --save                 # find the lights and remember them as the default
fairy on / off
fairy color red                   # name, #ff8800 or 255,100,0
fairy brightness 40
fairy preset fireworks -b 60      # built-in effect by number 1-58 or name; `fairy presets` lists names
fairy status / info

fairy image photo.png             # picture -> 20x20 (curtain only)
fairy image photo.png --fit cover --boost 1.4 --dry-run   # preview in the terminal, no Bluetooth
fairy text "HI" -c cyan
fairy clear
fairy move loop-left -s 30        # movement of the uploaded picture
fairy anim a.png b.png --mode breathe   # two-picture animation (experimental)
fairy shell                       # keeps the connection open, same commands
```

`fairy scan --all` lists every Bluetooth device nearby, in case your lights advertise under another name.
Dropped Bluetooth connections are recovered automatically (the status line shows `reconnected Nx`).

## Apps and games

All games and apps live in one menu, and they are started only from there:

```bash
fairy apps                        # arrow keys + Enter; q inside an app -> back to the menu; q in the menu -> quit
```

They run in real time from the keyboard and mirror the curtain in the terminal. Only changed pixels are sent over
Bluetooth. If the picture stutters, try `fairy apps --min-interval 0.1`. Options of `fairy apps` that configure
the apps in the menu:

| Option | Effect |
| --- | --- |
| `--dry-run` | terminal only, no Bluetooth (try everything without lights) |
| `--difficulty easy\|normal\|hard`, `--points N` | Pong: AI strength and points needed to win |
| `--camera N`, `--demo`, `--budget N` | Mirror: camera index, synthetic camera, max pixels sent per step |
| `--city NAME` | Weather: city (saved for next time) |

The menu has animations like an old TV: it switches on at start and off on exit (the picture collapses to a line,
then to a dot), and opening or closing an app shrinks the old picture to the centre like a window while the new
one grows out of it.

| App | Controls | Notes |
| --- | --- | --- |
| **Snake** | arrows / WASD | white border, speeds up, game-over animation |
| **Pong** | W/S or up/down | AI opponent, first to N points |
| **Tetris** | arrows, `x`/`z` rotate, space = hard drop, `p` pause | 10×18 field, next piece and level on the right, 7-bag |
| **Mario** | left/right, up/space = jump, `x` = fireball, `p` pause | see below |
| **Mirror** | left/right = look, space = new background | live webcam, see below |
| **Clock** | left/right = page | analog hands + digital, live |
| **Weather** | left/right = page | Open-Meteo, see below |

### Mario

Mario is 2 pixels tall (3 with a mushroom). The camera follows you to the right as you pass the middle of the
screen, like the original, and never scrolls back. Four generated levels, each ending with a flagpole, a castle
and fireworks, then a Bowser level that has to be beaten with fireballs, then the cycle repeats harder.

Level generation rules: safe flat start, at least 4 columns between obstacles, pipes 2 wide and 2–3 high (cannot
be entered), pits 2–3 wide, `?` blocks holding a mushroom, fire flower or coin (the first one always holds a
mushroom), koopas from level 2. The levels are tested to be beatable by a simple bot.

| Colour | Meaning |
| --- | --- |
| red | Mario (fire Mario has a white head), lives indicator top-left |
| orange | ground, stairs, used blocks |
| yellow | `?` block, Bowser's flames |
| green | pipe, Bowser |
| violet / cyan / blue | goomba / koopa / shell |
| magenta / lime | mushroom / fire flower |
| white | fireball, flagpole, castle |

### Webcam mirror

The Mirror app (needs the `camera` extra) shows your camera live, mirrored. Four looks (left/right):
*thermal* (brightness as a blue→red gradient, brightest white), *color* (real hues), *silhouette* (you in colour,
background off), *motion* (movement only). Per step only the biggest pixel changes are sent (`--budget`) and small
flicker is ignored (`--budget`). macOS asks for camera access on first use. `fairy apps --demo` uses a synthetic
camera, `--camera 1` picks another camera.

### Clock

Two pages: analog (red hour, yellow minute, cyan second hand, 12 ticks with the quarter hours in white) and
digital (HH:MM with a blinking colon, colour by time of day, weekday dots on top, seconds bar at the bottom).

### Weather

Set your city once with `fairy apps --city Berlin` (it is saved; afterwards plain `fairy apps` is enough). Data comes from
[Open-Meteo](https://open-meteo.com) (free, no API key) and refreshes every 10 minutes. Pages: icon + temperature,
today's high/low, rain probability for the next 6 hours. Temperature colour: blue < 0, cyan < 10, green < 20,
yellow < 28, red above. Settings live in `~/.config/hellofairy/config.json`.

## Hardware limits

- Each pixel can only be a **hue** (byte 0–180 ≙ 0–360°), **white** or **off** – no per-pixel brightness or
  saturation. Dark pixels become off, pale ones white (`--dark`, `--white`, `--boost` tune this).
- Image upload checks the device (400 LEDs, 20×20) and the BLE write capacity (≥ 242 bytes); `--force` skips the checks.
- A full upload takes about 3–4 s because of the hardware's pacing, so the real-time apps send only small changes.
- The two-picture animation is only confirmed for exactly two pictures.

## Troubleshooting

- **No device found** – switch the lights on, stay close, close the Hello Fairy phone app, allow Bluetooth for
  your terminal, and try `fairy scan --all`.
- **Camera unavailable** – allow your terminal under System Settings → Privacy & Security → Camera and close other
  apps that use the camera, or try `fairy apps --demo`.

## Development

```bash
.venv/bin/pip install -e '.[camera]' pytest
.venv/bin/pytest -q tests
```

The tests cover packet building against known vectors, all game logic, level generation (including a bot that
plays generated levels), and the Bluetooth reconnect logic with a fake radio. Layout of the code: `hellofairy/protocol.py` (pure packet
code), `ble.py` (transport), `arcade.py` (real-time runner), one module per app, `effects.py` (animations).

## iOS app (no Mac needed)

`HelloFairy/` is a native SwiftUI port (iOS 26, Liquid Glass) that talks to the lights over Bluetooth directly.
First start: pick your lights; afterwards it opens straight into the apps (arrows or swipe to choose, the choice
shows on the curtain). Controls are per app: Pong = finger up/down, Snake = swipe, Tetris = swipe/tap, Mario = buttons
+ swipe up, Mirror/Clock/Weather = swipe. Per-app settings are behind the gear. Leaving the Apps tab switches the
curtain off until you set something.

The unsigned IPA is built by `.github/workflows/ios.yml` (artifact `HelloFairy-unsigned-ipa`, or a release on `v*` tags);
sign it yourself (Sideloadly, AltStore, TrollStore). Logic tests: `swift test` (host, no simulator).
