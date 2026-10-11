# Contributing

Ringside is plain QML with two small helper scripts, so there's nothing to
build. Clone it and run `scripts/install.sh` to try your changes in a panel.

A running Plasma keeps the old QML until it restarts. To see your changes
without restarting it, open the installed widget in a window:

```bash
plasmawindowed dev.emily.ringside
```

## Running the tests

```bash
sh scripts/test.sh        # lint, then the QML, shell and Python tests
sh scripts/test-floor.sh  # the tests and the gallery on Plasma 6.0
sh scripts/gallery.sh     # every view in one picture, /tmp/ringside-gallery.png
```

`test.sh` and `gallery.sh` need Plasma 6.5 or later with libksysguard, Qt 6's
`qmllint`, `qmltestrunner` and `qml`, and Python 3.11 or later. If the Qt
tools aren't in `/usr/lib/qt6/bin` or `/usr/lib64/qt6/bin`, point `QMLLINT`,
`QMLTESTRUNNER` and `QML` at them. `shellcheck` and `reuse lint` run too if
you have them.

Older Plasma can't load its own module outside the shell, so `test-floor.sh`
runs the tests against a stand-in instead. CI uses it to check Plasma 6.0 on
Fedora 40.

A few more scripts:

```bash
sh scripts/pictures.sh    # the README's pictures, needs Pillow
python3 scripts/logo.py   # the logo and icon, needs fontTools, Nunito and rsvg-convert
sh scripts/package.sh     # ringside.plasmoid from the last commit
```

## Pull requests

Work on a branch and open a pull request against `main`. CI runs the tests
on it once it's out of draft, unless it only touches the README, this file,
the changelog or the pictures in `docs/`.

Nothing lands on `main` without the owner's go-ahead: pull requests open as
drafts, and marking one ready for review is that go-ahead, after which it
merges as soon as CI passes. Each change gets its own pull request and goes
in as one squashed commit. A release is a separate
pull request that bumps the version and dates the changelog, and is tagged
once it lands.

[AGENTS.md](AGENTS.md) has the project's ground rules: Plasma 6.0 support,
no new dependencies, privacy first, and how numbers and text are handled.
Have a look before anything big. A few smaller things:

- If you bump the version, change it in `package/metadata.json` and in
  `VERSION` in `usage.py`. A test checks they match.
- Journal lines go through `ui/code/log.js`, and the helper's come from the
  fixed `MESSAGES` in `usage.py`, so nothing private can end up in them. Keep
  `tests/python/test_journal.py` covering anything new.
  `QT_LOGGING_RULES="ringside.*.debug=true"` turns on the debug lines.
- In tests, map points with `mapToItem(item, Qt.point(x, y))`. Qt 6.6 rounds
  the separate `x, y` form to whole pixels.
- Commit titles name the part of Ringside changed and what changed:
  `usage: show an early reset in the popup`, `ci: cache the Fedora image`.
  Title a pull request the same way, since it becomes the squashed commit.
