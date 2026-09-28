# Ringside

A KDE Plasma 6 panel widget: CPU, GPU, memory, network and disk, plus optional
Claude Code and Codex weekly limits, as rings in the panel, each opening a
popup. Two layouts: Inline (a strip in any panel) and Standalone (large dials
in a dedicated panel that folds behind maximized windows). Pure QML with two
helper scripts; plugin id `dev.emily.ringside`; GPL-3.0-or-later; public at
github.com/emilyhamedian/ringside.

## Where things are

- `package/` is the widget. `contents/ui/main.qml` hosts both layouts and the
  single popup; `Monitor.qml` is the only place that subscribes to
  ksystemstats; `GpuReader.qml` with `code/gpugate.js` decides when a discrete
  GPU may be read; `UsageData.qml` runs `contents/code/usage.py` for the
  Claude and Codex items; `contents/code/ringside-info.sh` reports hardware
  facts ksystemstats doesn't publish.
- `tests/` holds the QtTest suites (`tests/qml/tst_*.qml`), the sh helper's
  fixtures (`tests/helper/`) and the Python helper's tests (`tests/python/`).
- `scripts/`: install, test, test-floor, gallery, pictures, package, add-panel.

## Direction

- Plasma 6.0 and later on any distribution; no Plasma 5. Keep
  `X-Plasma-API-Minimum-Version` at "6.0" (Add Widgets rejects 6.7 and up).
  Nothing newer than Qt 6.6 and KF 6.0 without a guarded fallback. Qt's
  JavaScript engine lacks some built-ins (`Array.prototype.flatMap`), and
  casts to inline components fail on Qt 6.6.
- No compiled code and no new runtime dependencies. System readings come from
  ksystemstats through libksysguard's QML modules; anything else from the
  POSIX sh helper, reading /proc, /sys and udev as the user. Python 3.11
  (stdlib only) is used only by the opt-in Claude and Codex items.
- One Sensor per ksystemstats id in a widget, and one reader per GPU across
  widgets (`code/gpushare.js`): duplicate subscriptions leak in ksystemstats
  and keep a discrete GPU awake. Never subscribe a suspended GPU.
- The Claude helper shares a tight rate limit and single-use refresh tokens
  with Claude Code and other tools on the same machine. Keep the 5-minute
  floor, the cache, the lock and the re-read-before-write on refresh.
- Numbers go through `code/format.js` (locale digits, binary units);
  user-visible strings through `i18nc` in QML, since `.pragma library` files
  can't translate. Colours come from the Plasma theme.
- Comments explain intent in plain sentences. The README is for people
  installing the widget: short, plain, no filler.

## Checks

- `sh scripts/test.sh` must pass on a Plasma 6.5 or later desktop: qmllint (only
  unqualified i18n warnings accepted), the QtTest suites including the de_DE
  and ar_EG runs, the helper fixtures and the Python tests.
  `sh scripts/gallery.sh` renders every state for a visual check.
- A running plasmashell keeps old QML until it restarts;
  `plasmawindowed dev.emily.ringside` runs the installed widget in a window.

## Git

See CONTRIBUTING.md for the checks and style. Work on a branch. Nothing lands on `main` without the owner's go-ahead, and
it lands as one squashed commit: `main` is what people install from. Releases
are tagged on `main` and carry `ringside.plasmoid` from `scripts/package.sh`.
