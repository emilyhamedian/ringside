# Ringside

A KDE Plasma 6 panel widget: CPU, GPU, memory, network and disk, plus optional
Claude Code and Codex weekly limits, as rings in the panel, each opening a
popup. Pure QML with two helper scripts; plugin id `dev.emily.ringside`;
GPL-3.0-or-later.

## Where things are

- `package/contents/` is the widget:
  - `ui/main.qml`: the panel strip and the single popup.
  - `ui/Monitor.qml`: every reading; the only place that subscribes to
    ksystemstats.
  - `ui/GpuReader.qml` with `ui/code/gpugate.js`: when a discrete GPU may
    be read.
  - `ui/UsageData.qml`: runs `code/usage.py` for the Claude and Codex items
    and their opt-in session starter.
  - `ui/PublicAddress.qml`: asks for the address the network popup shows.
  - `ui/HistoryStore.qml`: keeps the graphs' hour and day when that setting
    is on; the only file that imports Qt's optional LocalStorage module.
  - `ui/code/pace.js`: a weekly limit's pace, for the panel and the popup.
  - `code/ringside-info.sh`: hardware facts ksystemstats doesn't publish.
- `tests/`:
  - `qml/tst_*.qml`: the QtTest suites.
  - `helper/`: the sh helper's fixtures.
  - `python/`: the Python helper's tests.
  - `floor/`: a stand-in Plasma module for the Plasma 6.0 floor run.
- `scripts/`: install, test, test-floor, gallery, pictures, logo, package.

## Direction

In this file, must and must not are requirements, should is the expected way
unless there's a good reason to differ, and may is allowed but optional.

- Ringside must support Plasma 6.0 and later on any distribution, and not
  Plasma 5. `X-Plasma-API-Minimum-Version` must stay at "6.0" (Add Widgets
  rejects 6.7 and up). Nothing newer than Qt 6.6 and KF 6.0 may be used
  without a guarded fallback. Qt's JavaScript engine lacks some built-ins
  (`Array.prototype.flatMap`), and casts to inline components fail on Qt 6.6.
- There must be no compiled code and no new runtime dependencies. System
  readings must come from ksystemstats through libksysguard's QML modules;
  anything else from the POSIX sh helper, reading /proc, /sys and udev as the
  user. Python 3.11 (stdlib only) must be used only by the opt-in Claude and
  Codex items.
- A widget must have one Sensor per ksystemstats id, and there must be one
  reader per GPU across widgets (`code/gpushare.js`): duplicate subscriptions
  leak in ksystemstats and keep a discrete GPU awake. A suspended GPU must
  not be subscribed.
- Private by default. A fresh install must contact nothing beyond this
  machine. Anything that reaches the internet must be the user's choice: off
  until they turn it on, plain about what it sends and to whom, sending no
  more than it needs and as rarely as it can, and keeping what it learns on
  the machine.
- A guest in the user's Claude and Codex accounts. Their own tools share the
  same logins and limits, so Ringside must never cost them a sign-in, a rate
  limit or usage they didn't ask for, and anything that spends usage must be
  a switch only the user turns on.
- Numbers must go through `code/format.js` (locale digits, binary units), and
  user-visible strings through `i18nc` in QML, since `.pragma library` files
  can't translate. Colours must come from the Plasma theme.
- Comments should explain intent in plain sentences. The README should serve
  people installing the widget: short, plain, no filler.
- The rings hide an easter egg (`ui/Egg.qml`). It must not appear in anything
  users read: README, CHANGELOG, release notes, PR text and settings.
- The widget's runtime logging (what Ringside writes to the user's journal
  under `ringside.*` categories) should record failures and state changes by
  default and per-check detail only at debug. It must never include tokens,
  account details, addresses, cities or file contents.

## Checks

- `sh scripts/test.sh` must pass on a Plasma 6.5 or later desktop: qmllint (only
  unqualified i18n warnings accepted), the QtTest suites including the de_DE
  and ar_EG runs, the helper fixtures and the Python tests.
  `sh scripts/gallery.sh` renders every state for a visual check.
- A running plasmashell keeps old QML until it restarts;
  `plasmawindowed dev.emily.ringside` runs the installed widget in a window.

## Git

See CONTRIBUTING.md for the checks, style and required approval. Work must
happen on a branch. Each change must land as one squashed commit: `main` is
what people install from. Releases must be tagged on `main` and carry
`ringside.plasmoid` from `scripts/package.sh`.
