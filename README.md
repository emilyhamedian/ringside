# Ringside

CPU, GPU, memory, network and disk at a glance in a KDE Plasma 6 panel.

<!-- screenshots: docs/panel.png, docs/popups.png -->

Each item is a ring or a pair of rates in the panel. Click one for a popup
under it with history graphs, per-thread load, top processes, VRAM, clocks,
power, swap, memory pressure and disk activity.

- **CPU**: usage ring and temperature.
- **GPU**: a discrete GPU on the outer ring and an integrated one on the inner
  ring, with both temperatures. With one GPU there is one ring.
- **Memory**: usage ring and the amount in use.
- **Network**: download and upload rates.
- **Disk**: read and write rates (hidden by default; the network popup shows
  disk activity too).

Temperatures turn amber and red above thresholds you set. Colours follow your
Plasma theme, and the widget works on any panel edge.

### Discrete GPUs on laptops

Reading a GPU's sensors keeps it awake. A laptop's discrete GPU normally
powers down when nothing uses it, so Ringside only reads it while it is
already awake, lets go after it has sat idle for a few seconds, and shows
**off** while it sleeps. Opening the GPU popup never wakes it.

Other widgets that show the same GPU's sensors, such as Plasma's own GPU
monitors, keep it awake regardless.

## Requirements

- KDE Plasma 6.0 or later. Tested on Plasma 6.7 with KDE Frameworks 6.30 and
  Qt 6.11.
- ksystemstats and libksysguard, which every Plasma 6 desktop ships for the
  System Monitor.
- Memory pressure needs Plasma 6.2 or later, and Intel GPU readings 6.4 or
  later; without them those parts are left out.

## Install

```bash
git clone https://github.com/emilyhamedian/ringside.git
cd ringside
scripts/install.sh
```

Then add **Ringside** to a panel from *Add Widgets*.

To update:

```bash
git pull
scripts/install.sh
systemctl --user restart plasma-plasmashell
```

Plasma keeps running the old version until it restarts or you log in again.

To uninstall, remove the widget from the panel, then:

```bash
kpackagetool6 --type Plasma/Applet --remove dev.emily.ringside
```

## Settings

Right-click the widget and choose *Configure Ringside*.

- **General**: update interval, how far back the graphs reach, Celsius or
  Fahrenheit, network rates in bits or bytes, temperature highlight thresholds.
- **Panel Items**: which items show and in what order, rings with or without
  their text, ring size.
- **Sensors**: the CPU temperature source, which GPU goes on which ring, the
  network interface, the disk and volume, and the disk temperature sensor.

## What it reads

Readings come from ksystemstats, the service behind Plasma's System Monitor.
A small shell script,
[`ringside-info.sh`](package/contents/code/ringside-info.sh), fills in what
ksystemstats doesn't publish: the CPU model, memory module type and speed,
GPU marketing names and which GPU is integrated, the disk holding `/`, and
whether the discrete GPU is asleep. It reads `/proc`, `/sys` and udev's
database as your user and needs no root. Nothing leaves the machine.

## Development

```bash
scripts/test.sh      # qmllint, QML unit tests and the helper's fixture tests
scripts/gallery.sh   # renders the strip and every popup to /tmp/ringside-gallery.png
```

Both run on a Plasma 6 host and use the Qt 6 tools in `/usr/lib/qt6/bin`.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
