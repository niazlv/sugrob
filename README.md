<div align="center">

<img src="docs/icon.png" width="112" alt="">

# Sugrob

**Physically simulated snow for your Mac desktop**

English · [Русский](README.ru.md)

[![Release](https://img.shields.io/github/v/release/niazlv/sugrob?label=release&color=4f7be0)](https://github.com/niazlv/sugrob/releases/latest)
![macOS 13+](https://img.shields.io/badge/macOS-13%2B-25336b)
[![MIT license](https://img.shields.io/badge/license-MIT-8aa4d6)](LICENSE)
[![Build](https://github.com/niazlv/sugrob/actions/workflows/build.yml/badge.svg)](https://github.com/niazlv/sugrob/actions/workflows/build.yml)

<img src="docs/hero.webp" width="900" alt="The cursor pushes snow off a window; it pours onto the Dock, and a quick flick scatters the pile">

**[Download Sugrob.zip](https://github.com/niazlv/sugrob/releases/latest/download/Sugrob.zip)**

</div>

Sugrob (Russian for “snowdrift”) lives in the menu bar. Snow falls over your desktop, settles on
windows, the Dock and the bottom of the screen, and from then on behaves like snow: you can brush
it away, push it off an edge or roll it into a ball. Clicks pass straight through, so it never
gets in the way of work.

<table>
<tr>
<td width="50%"><img src="docs/snowman.webp" alt="Three snowballs are rolled and stacked"><br><b>Snowman.</b> A ball grows as it rolls. Stack three of them.</td>
<td width="50%"><img src="docs/people.webp" alt="Little people finish a ladder and climb onto a window"><br><b>Visitors.</b> They build a ladder out of snow and climb onto your window.</td>
</tr>
<tr>
<td><img src="docs/tree.webp" alt="One of the little people carries in a Christmas tree and plants it in the snow"><br><b>Christmas tree.</b> Sooner or later someone drags one in.</td>
<td><img src="docs/storm.webp" alt="Wind drives snow across the screen and strips it off a window"><br><b>Snow squall.</b> It arrives uninvited, strips the caps off windows and sends snow drifting.</td>
</tr>
</table>

## What it does

- **Snow that acts like snow.** Settled snow is a grid of small cubes. Anything knocked loose flies
  off in chunks, slides down slopes and settles again; volume is conserved. Over time snow packs
  down, slumps and freezes into a blue icy crust.
- **You can touch it.** Brush it away with the cursor, push it off a window edge, roll a ball,
  throw a snowball, build a snowman.
- **It sticks to your windows.** Drag a window and its drift rides along; close it and the snow
  falls. Each desktop (Space) keeps its own snow.
- **Little people.** Every so often a group in parkas and bobble hats wanders in. They have
  snowball fights, build snowmen, dig tunnels and pull each other on sledges. If one of them gets
  buried, the others run to dig them out. Some stay for good and build an igloo.
- **Weather.** Light snow, steady snowfall or a blizzard, wind in either direction, and a squall
  that turns up whenever it likes.
- **It doesn't peek.** No screen recording, no accessibility access. The app reads window frames
  only, never titles or contents.

Everything can be adjusted or switched off from the ❄ menu.

## Install

1. Download [Sugrob.zip](https://github.com/niazlv/sugrob/releases/latest/download/Sugrob.zip)
   and move `Sugrob.app` to Applications.
2. The app is not notarized by Apple, so the first launch needs your approval: try to open it,
   then go to **System Settings → Privacy & Security** and click **Open Anyway**. Or remove the
   quarantine flag in Terminal:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Sugrob.app
   ```

3. There is no window. Look for the ❄ icon in the menu bar.

Requires macOS 13 or later. The build is universal (Apple Silicon and Intel), but it has been used
day to day only on Apple Silicon with macOS 26.

Sugrob updates itself: every few hours it checks this repository's releases and installs a new
version while the Mac is idle. The update manifest is signed, and automatic updates can be turned
off in the menu.

## Controls

| To do this | Do this |
| --- | --- |
| Brush snow away | Move the cursor through a drift |
| Scatter snow | Flick the cursor through it |
| Make a snowball | Hold `⌃⌥`, press the mouse button on snow and drag |
| Throw a snowball | Release while moving |
| Build a snowman | Lower a ball gently onto the top of another |
| Pick a ball up again | Hold `⌃⌥` and press on it |
| Crack the icy crust | Strike it sharply with the cursor, or throw a snowball |
| Tease the little people | Clip one with a fast cursor or a ball, and expect a snowball back |

<details>
<summary><b>The menu is in Russian for now. Here is a glossary.</b></summary>

| In the menu | Meaning |
| --- | --- |
| Поставить снег на паузу / Вернуть зиму | Pause the snow / bring it back |
| Насыпать снег сейчас | Cover every surface with snow right now |
| Убрать весь снег | Remove all snow |
| Погода: Лёгкий снег, Снегопад, Метель | Weather: light snow, snowfall, blizzard |
| Погода → Ветер, Штиль | Wind, calm |
| Погода → Иногда налетает буран | A snow squall blows in now and then |
| Сугробы: Низкие, Средние, Высокие | Drift height: low, medium, high |
| Сугробы → Растут сами | Drifts grow on their own (off: only flakes that actually land build them) |
| Сугробы → Слёживаются и подмерзают | Snow packs down and freezes over time |
| Сугробы → Курсор смахивает снег | The cursor brushes snow |
| Сугробы → Где лежит снег | Where snow may settle: windows, widgets, the Dock, the bottom of the screen |
| Человечки | Little people: how often they visit and what they are allowed to do |
| Внешний вид | Appearance: voxel size and the window corner radius used for the snow line |
| Как играть | How to play: a list of hints |
| О Сугробе | About Sugrob |
| Запускать при входе | Launch at login |
| Обновления | Updates |
| Выйти из Сугроба | Quit |

</details>

## Resource use

Sugrob is light on the processor and memory. What it does cost is a little GPU time: the
transparent layer over your desktop is redrawn 60 times a second, and the Mac's window compositor
has to blend it each time. Measured on version 1.4, MacBook Pro with an M1 Max, a 3456×2234
display and macOS 26, plugged in, with the app in its usual state:

| | |
| --- | --- |
| CPU | about 2 % of the chip, almost all of it on efficiency cores: 0.1 W |
| Memory | 100–110 MB |
| GPU | 2–3 % of the GPU's time for the snow itself |
| System processes | about +1.5 % of the chip in `WindowServer` and `launchservicesd` |
| **Whole Mac, extra power** | **about 1 W** (0.9–1.4 W), mostly GPU and compositor |

Activity Monitor counts one core as 100 %, so it shows Sugrob at about 20 %. The M1 Max has ten
cores, which makes that 2 % of the chip.

That is not nothing: on a laptop battery it is roughly 1–2 % of the charge per hour, or 5–15 %
off the runtime, depending on what else the Mac is doing. It is small next to what warms a Mac
or spins up a fan, which is tens of watts.

<details>
<summary><b>How this was measured</b></summary>

- CPU and memory: `top`, `footprint` and `proc_pid_rusage` (the per-process energy counter).
- GPU time: the per-process counters of the `IOAccelerator` service.
- Energy: the chip's own CPU, GPU and DRAM energy counters (IOReport, no root needed), with the
  app alternately running and frozen with `SIGSTOP` in 15-second windows, six pairs. The GPU
  difference was steady (+0.8 W median). CPU readings for the whole chip were swamped by other
  apps, so the CPU and system-process shares are estimated from the load they add.
- The whole-Mac figure is an order of magnitude, not a precise number. Not measured: blizzards,
  a crowd of little people, several displays, an Intel Mac.

</details>

## Build from source

You need Xcode or its command-line tools (Swift 5.9 or later). There are no dependencies.

```bash
./build.sh
```

The app is written to `build/Sugrob.app`. The simulation does not depend on the UI and is tested
headless; GitHub Actions runs the same stress test on every push:

```bash
.build/release/Sugrob --fuzz 300 1 3
```

<details>
<summary><b>How it works</b></summary>

- **Two states of snow.** Settled snow lives in a grid: one byte per cell, plus a “hardness” byte
  for ageing. Loose snow is a list of particles with velocity, gravity and wind. A cell that loses
  its support becomes a particle; a particle that lands on something becomes a cell.
- **Ledges.** The top edges of visible windows, the Dock and the bottom of the screen. Window
  frames come from `CGWindowListCopyWindowInfo`, which needs no permission as long as titles are
  not read.
- **Rendering.** One transparent, click-through Metal layer per desktop. The grid is uploaded as a
  texture and shaded in a fragment shader.
- **Input.** The cursor position and modifier keys are polled, so no events have to be intercepted.
  The layer captures the mouse only while `⌃⌥` is held.
- **The little people** are part of the same simulation, not a cartoon drawn over it. A snowball
  is made of cells taken from a drift, ladder steps are trampled snow, and an avalanche really
  does bury whoever is underneath.

The identifier of the current desktop and the Dock's rectangle come from undocumented macOS calls
that are looked up at launch. If they are missing, the app falls back to one shared layer and an
estimated Dock size.

The animations on this page are recorded by `tools/readme-media/make.sh`, using the same
simulation with no screen attached.

</details>

## Support

<div align="center">

<img src="docs/village.webp" width="640" alt="Little people warm themselves at a campfire between igloos">

<sub>The campfire runs on donations.</sub>

</div>

Sugrob is free, with no ads and no subscriptions. There is exactly one subscription involved: the
author's Claude plan, and that is where donations go. If you know, you know. If you don't, think
of it as buying the author a coffee, except that a neural network drinks it.

<div align="center">

<img src="docs/donate-btc.png" width="150" alt="QR code: Bitcoin address">&nbsp;
<img src="docs/donate-eth.png" width="150" alt="QR code: Ethereum address">&nbsp;
<img src="docs/donate-bnb.png" width="150" alt="QR code: BNB Chain address">&nbsp;
<img src="docs/donate-sol.png" width="150" alt="QR code: Solana address">&nbsp;
<img src="docs/donate-trx.png" width="150" alt="QR code: Tron address">

<sub>Click a card to open it on its own at full size, which makes it easier to scan.</sub>

</div>

| Network | Address |
| --- | --- |
| Bitcoin | `bc1qyt9hzvtd69t5jkk7h39fqd4pz7tg9jl9pq4arf` |
| Ethereum (ERC-20)<br><sub>also Base, Arbitrum, Optimism, Polygon, Linea</sub> | `0xBA10A984A88AeE82A2D3b30EA6d91BC554D46A25` |
| BNB Chain (BEP-20) | `0xBA10A984A88AeE82A2D3b30EA6d91BC554D46A25` |
| Solana | `9GhoGBorb8xvkUjFgGfrcFun1m6ad9K9chDUhvagXYwX` |
| Tron (TRC-20) | `TKyahQhTeLdMraKDbedLz17jorRTfER8xX` |

In your wallet, pick the same network as in the row with the address: a transfer sent on any other
network will not arrive.

## License

[MIT](LICENSE)
