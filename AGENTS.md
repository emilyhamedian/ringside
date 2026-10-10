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
- Private by default. A fresh install contacts nothing beyond this machine.
  Anything that reaches the internet is the user's choice: off until they
  turn it on, plain about what it sends and to whom, sending no more than it
  needs and as rarely as it can, and keeping what it learns on the machine.
- A guest in the user's Claude and Codex accounts. Their own tools share the
  same logins and limits, so Ringside never costs them a sign-in, a rate
  limit or usage they didn't ask for, and anything that spends usage is a
  switch only the user turns on.
- Numbers go through `code/format.js` (locale digits, binary units);
  user-visible strings through `i18nc` in QML, since `.pragma library` files
  can't translate. Colours come from the Plasma theme.
- Comments explain intent in plain sentences. The README is for people
  installing the widget: short, plain, no filler.
- The rings hide an easter egg (`ui/Egg.qml`). Keep it out of everything
  users read: README, CHANGELOG, release notes, PR text and settings.

## Checks

- `sh scripts/test.sh` must pass on a Plasma 6.5 or later desktop: qmllint (only
  unqualified i18n warnings accepted), the QtTest suites including the de_DE
  and ar_EG runs, the helper fixtures and the Python tests.
  `sh scripts/gallery.sh` renders every state for a visual check.
- A running plasmashell keeps old QML until it restarts;
  `plasmawindowed dev.emily.ringside` runs the installed widget in a window.

## Git

See CONTRIBUTING.md for the checks, style and required approval. Work on a
branch. Each change lands as one squashed commit: `main` is what people
install from. Releases
are tagged on `main` and carry `ringside.plasmoid` from `scripts/package.sh`.
