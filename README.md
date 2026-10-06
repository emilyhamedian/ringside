# Ringside

[![Tests](https://github.com/emilyhamedian/ringside/actions/workflows/test.yml/badge.svg?branch=main)](https://github.com/emilyhamedian/ringside/actions/workflows/test.yml)
[![Release](https://img.shields.io/github/v/release/emilyhamedian/ringside)](https://github.com/emilyhamedian/ringside/releases/latest)
[![License: GPL-3.0-or-later](https://img.shields.io/github/license/emilyhamedian/ringside)](LICENSE)

CPU, GPU, memory, network and disk in a KDE Plasma 6 panel, and your Claude
and Codex usage limits if you want them.

![Ringside in a panel: CPU, GPU and memory rings with their names inside, each with its usage over its temperature or the memory in use, a Claude ring with its weekly usage over the days to its reset and its Fable limit in red on the inner ring, then network rates](docs/panel.png)

Each item is a ring with its name inside and its readings beside it, or a
pair of rates. Items are as wide as their text, with the same gap between
each. When a reading gains a character, the items after it move over at
once; when it loses one, they wait three minutes before closing up, so a
value that keeps changing width doesn't shuffle the panel.

Click an item for its popup: history graphs, per-thread load, top
processes, VRAM, clocks, power, swap, memory pressure and disk activity.
Percentage graphs have a line at 100%; rate graphs reach up to their peak,
which the caption names. Temperature sensors go by plain names such as chip
and hotspot.

![The CPU, GPU, memory and network popups](docs/popups.png)

- **CPU**: usage and temperature.
- **GPU**: a discrete GPU on the outer ring and an integrated one on the inner
  ring, with the outer one's temperature; the popup shows both. With one GPU
  there is one ring.
- **Memory**: usage and the amount in use.
- **Network**: download and upload rates.
- **Disk**: read and write rates. Off by default; the network popup shows disk
  activity too.
- **Claude** and **Codex**: how much of the weekly limit is used and when it
  resets. Off by default; see below.

Rings and their percentages turn amber at 75% and red at 90%. Temperatures
turn amber and red above thresholds you set; a ring shown without its text
turns with its temperature too. Colours follow your Plasma theme.

## Install

Download `ringside.plasmoid` from the
[latest release](https://github.com/emilyhamedian/ringside/releases/latest),
then either open *Add or Manage Widgets…*, choose *Get New… → Install Widget
From Local File…* and pick the file, or run:

```bash
kpackagetool6 --type Plasma/Applet --install ringside.plasmoid
```

Then add **Ringside** to a panel from *Add or Manage Widgets…*. Before Plasma
6.2 these read *Add Widgets…* and *Get New Widgets…*.

To update, download the new file and run:

```bash
kpackagetool6 --type Plasma/Applet --upgrade ringside.plasmoid
```

Plasma keeps running the old version until plasmashell restarts. Log out and
back in, or where systemd runs Plasma (most distributions):

```bash
systemctl --user restart plasma-plasmashell
```

To uninstall, remove the widget from its panel, then:

```bash
kpackagetool6 --type Plasma/Applet --remove dev.emily.ringside
```

### From source

```bash
git clone https://github.com/emilyhamedian/ringside.git
cd ringside
scripts/install.sh
```

`git pull` and `scripts/install.sh` again to update.

## Requirements

- KDE Plasma 6.0 or later.
- ksystemstats and libksysguard, which come with Plasma's System Monitor.
- Memory pressure needs Plasma 6.2 or later. Intel GPUs need 6.4 or later with
  the i915 driver, or 6.8 or later with xe, and report no temperature or VRAM.
  Without those, the parts are left out.
- Claude and Codex need Python 3.11 or later.

## Claude and Codex

![The Claude popup: the weekly limit, the Fable limit in red with a sentence saying when it runs out at this pace, and a graph of this week's usage](docs/usage.png)

Turn them on under *Configure Ringside… → Panel Items*. Each shows while its
command-line tool is signed in on this machine; if one doesn't appear, its row
under *Panel Items* says why.

- **Claude** needs [Claude Code](https://docs.claude.com/en/docs/claude-code)
  signed in with a Claude subscription. Ringside reads its login from
  `~/.claude/.credentials.json` and asks Anthropic's usage service for the
  limits. Each check's result, even an error or a sign-out, is kept for five
  minutes and shared by every Ringside widget; when Anthropic asks it to wait
  longer, it waits that long, up to a day. When the login has expired it
  renews it the way Claude Code does and saves it back, so Claude Code stays
  signed in.
- **Codex** needs the [Codex CLI](https://github.com/openai/codex) signed in.
  Ringside runs `codex app-server` to ask for the limits.

The ring shows the weekly limit for all models, over the time left until it
resets: the days alone ("6d") until the last day, then hours and minutes.
At 100% that time turns red, since it's how long the limit stays reached. If
your plan also has a per-model weekly limit, the inner ring shows it; choose
which under *Sensors*. Model limits are the ones Anthropic's usage reply
lists, under the names it gives them, such as Fable.

A ring also turns red when its limit is on pace to run out before the reset,
at the rate it has been used so far. When the last check failed, a small
amber dot sits at the ring's corner and the tooltip says when.

The popup lists every weekly limit and when each resets, and a graph of the
week so far, which fills in as Ringside keeps checking. The graph has a line
at 100% and a tick at the reset, and a limit on pace to run out gets a dotted
line to where it would reach 100%. From a day into the week, or sooner if a
limit is running out, a sentence says where it is heading: "At this pace, 88%
by the reset", or "At this pace, Fable runs out Thu 8:20 PM". Reset times
follow the time zone of Plasma's Digital Clock.

## Discrete GPUs on laptops

Reading a GPU's sensors keeps it awake. A laptop's discrete GPU normally
powers down when nothing uses it, so Ringside reads it only while something
else has woken it and lets go after about ten idle seconds. While it sleeps,
the GPU item shows only the integrated GPU, as on a machine with one GPU.
Opening the GPU popup never wakes it.

If the GPU stays awake anyway, say for a display on its outputs, Ringside reads
it again and waits longer before each next try, up to five minutes. Other
widgets that read the same GPU's sensors, such as Plasma's own GPU monitors,
keep it awake regardless.

## Settings

Right-click the widget and choose *Configure Ringside…*.

- **General**: update interval, how far back the graphs reach, Celsius or
  Fahrenheit, network rates in bits or bytes, temperature thresholds, and how
  often Claude and Codex are checked.
- **Panel Items**: which items show and in what order, and rings with or
  without their text. Rings grow and shrink with the panel.
- **Sensors**: the CPU temperature source, which GPU goes on which ring, the
  network interface, the disk and volume, the disk temperature sensor, and the
  Claude and Codex inner rings.

## What it reads

System readings come from ksystemstats, the service behind Plasma's System
Monitor. A shell script,
[`ringside-info.sh`](package/contents/code/ringside-info.sh), adds what
ksystemstats doesn't publish, such as the CPU model, memory type, GPU names and
whether the discrete GPU is asleep. It reads `/proc`, `/sys` and udev's
database as your user.

The Claude and Codex items run
[`usage.py`](package/contents/code/usage.py). It sends your Claude Code login
only to Anthropic (`api.anthropic.com`, and `platform.claude.com` to renew it),
and asks the Codex CLI on your machine for Codex. It keeps the last readings
and the week's history in `~/.cache/ringside/`.

## Development

```bash
sh scripts/test.sh        # qmllint, the QML tests, the helpers' tests, shellcheck, reuse lint
sh scripts/test-floor.sh  # the tests and the gallery on Plasma 6.0
sh scripts/gallery.sh     # renders every view to /tmp/ringside-gallery.png
sh scripts/pictures.sh    # renders the pictures in docs/ from sample readings
sh scripts/package.sh     # builds ringside.plasmoid from the last commit
```

The full tests, gallery and pictures need Plasma 6.5 or later, which ships
the QML modules they load. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
