# Sugrob

**Physically simulated snow for your Mac desktop.**

English · [Русский](README.ru.md)

![build](https://github.com/niazlv/sugrob/actions/workflows/build.yml/badge.svg)

![A snowman built on top of a window](docs/snowman.png)

Sugrob (Russian for “snowdrift”) is a small menu-bar app. Snow falls over your desktop, settles on
the top edges of windows, on the Dock, on desktop widgets and along the bottom of the screen — and
then behaves like snow. You can brush it away with the cursor, push it off a window edge, roll it
into balls, throw snowballs and build a snowman. Clicks pass straight through, so it never gets in
the way of work.

| Pushing snow off a window | Old snow turns into an icy crust |
| --- | --- |
| ![Snow pouring off a window edge](docs/push.png) | ![Frozen crust on a window](docs/crust.png) |

## What it does

- **Voxel snow.** Settled snow is a grid of small cubes; anything knocked loose becomes flying
  chunks that land, slide down slopes and settle again. Volume is conserved.
- **Brush and plough.** Move the cursor through a drift: slowly, and it pushes a wave of snow ahead
  of it; with a quick flick, snow flies off.
- **Snowballs.** Hold `⌃⌥` and drag to scoop a ball. It rolls on top of the snow and winds up the
  surface layer, so it grows as it travels. Let go on the move to throw it — a hard hit bursts it.
- **Snowmen.** Lower one ball gently onto another and it sticks. The top ball gets eyes, a carrot
  and a smile.
- **Balls have weight and age.** They roll downhill on their own. A heavy ball sinks into soft
  snow, compacts it and ploughs a berm ahead of itself. A ball left standing freezes in place,
  gets snowed over, slumps and finally becomes a drift.
- **Snow ages.** Fresh snow is loose. After a few minutes it packs down; later it freezes into a
  blue icy crust the cursor just slides over — crack it with a sharp strike or a snowball.
- **It follows your windows.** Drag a window and its snow rides along; close it and the snow falls.
  The snow line follows rounded window corners. Each desktop (Space) keeps its own snow.
- **Weather.** Light snow, steady snowfall or a blizzard; wind in either direction; drift height;
  voxel size.
- **No permissions.** No screen recording, no accessibility access. The app only reads window
  frames — never titles or contents.

Everything can be switched on and off from the ❄ menu.

## Install

1. Download `Sugrob.zip` from the [latest release](https://github.com/niazlv/sugrob/releases/latest).
2. Unzip it and move `Sugrob.app` to Applications.
3. The app is not notarized by Apple, so the first launch needs your approval: try to open it,
   then go to **System Settings → Privacy & Security** and click **Open Anyway**. Or remove the
   quarantine flag in Terminal:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Sugrob.app
   ```

Requires macOS 13 or later. The build is universal (Apple Silicon and Intel); it has been used
day to day only on Apple Silicon with macOS 26.

There is no window: look for the ❄ icon in the menu bar.

## Controls

| Action | How |
| --- | --- |
| Brush snow away | Move the cursor through it |
| Throw snow | Flick the cursor through a drift |
| Make a snowball | Hold `⌃⌥`, press the mouse button on snow and drag |
| Throw a snowball | Release while moving |
| Build a snowman | Lower a ball gently onto the top of another |
| Pick a ball up again | Hold `⌃⌥` and press on it |
| Roll a loose ball | Just push it with the cursor |
| Crack the icy crust | A sharp strike with the cursor, or a snowball |

## The menu

The interface is in Russian for now. This is what the items mean:

| Menu item | Meaning |
| --- | --- |
| Поставить снег на паузу / Вернуть зиму | Pause the snow / bring it back |
| Погода → Лёгкий снег, Снегопад, Метель | Weather: light snow, snowfall, blizzard |
| Ветер | Wind: strong left, left, calm, right, strong right |
| Сугробы → Низкие, Средние, Высокие | Drift height: low, medium, high |
| Размер вокселя | Voxel size: small, medium, large, extra large |
| Сугробы растут сами | Drifts grow on their own (off: only flakes that actually land build them) |
| Где лежит снег | Where snow may lie: windows, windows touching the menu bar, narrow windows, desktop widgets, bottom of the screen, the Dock; “don't lie over other windows” |
| Скругление углов окон | Window corner radius used for the snow line: none, small, medium, large |
| Курсор смахивает снег | The cursor brushes snow |
| Снег слёживается и подмерзает | Snow packs down and freezes over time |
| Насыпать снег сейчас | Fill all surfaces with snow right now |
| Убрать весь снег (лопата) | Remove all snow |
| Обновления | Updates: check now, update automatically |
| Запускать при входе | Launch at login |
| Выйти из Сугроба | Quit |

## Build from source

You need Xcode (or its command-line tools) with Swift 5.9 or later. There are no dependencies.

```bash
./build.sh          # build/Sugrob.app for this Mac
./build.sh --dist   # universal build/dist/Sugrob.app and build/Sugrob.zip
```

The simulation is independent of the UI and can be tested headless:

```bash
.build/release/Sugrob --fuzz 300 1 3      # 300 simulated seconds of random abuse, seed 1, 3 pt voxels
.build/release/Sugrob --selftest shots    # scripted scenario rendered to PNG files in ./shots
```

The fuzz run fails if any simulation step takes too long, which is how a hang is caught before it
reaches a real desktop. Every push is built and stress-tested by GitHub Actions.

## How it works

- **Two states of snow.** Settled snow lives in a grid (one byte per voxel, plus a “hardness”
  byte for ageing). Loose snow is a list of particles with velocity, gravity and wind. A voxel that
  loses support becomes a particle; a particle that lands becomes a voxel and slides until the
  slope is gentle enough.
- **Ledges.** The top edges of visible windows, the Dock and the bottom of the screen are supports.
  Window frames come from `CGWindowListCopyWindowInfo`, which needs no special permission as long
  as window titles are not read.
- **Rendering.** One transparent, click-through Metal layer per desktop. The grid is uploaded as a
  texture and shaded in a fragment shader; particles are drawn as points.
- **Input.** The cursor position and modifier keys are polled, so the layer never has to intercept
  events. It only captures the mouse while `⌃⌥` is held.

Two things rely on undocumented macOS calls, looked up at run time: the identifier of the current
desktop (so each one can have its own snow) and the Dock's rectangle. If they are missing, the app
falls back to one shared layer and an estimated Dock size.

## Updates

The app checks this repository's releases for a new version every few hours. Update manifests are
signed, and an update is installed only when the Mac has been idle for a minute. Automatic
updates can be turned off under **Обновления** in the menu.

## Support

If Sugrob made your desktop a little cosier, you can support its development. Please send only on
the network listed next to the address.

| Network | Address |
| --- | --- |
| Bitcoin (Native SegWit) | `bc1qyt9hzvtd69t5jkk7h39fqd4pz7tg9jl9pq4arf` |
| Ethereum | `0xBA10A984A88AeE82A2D3b30EA6d91BC554D46A25` |
| BNB Chain (BEP-20) | `0xBA10A984A88AeE82A2D3b30EA6d91BC554D46A25` |
| Base | `0xBA10A984A88AeE82A2D3b30EA6d91BC554D46A25` |
| Polygon | `0xBA10A984A88AeE82A2D3b30EA6d91BC554D46A25` |
| Solana | `9GhoGBorb8xvkUjFgGfrcFun1m6ad9K9chDUhvagXYwX` |
| Tron (TRC-20) | `TKyahQhTeLdMraKDbedLz17jorRTfER8xX` |

The Ethereum address is the same on Arbitrum, Optimism and Linea.

## License

[MIT](LICENSE)
