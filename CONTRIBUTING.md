# Contributing

## Checks

```bash
sh scripts/test.sh        # qmllint, the QML tests, the helpers' tests, shellcheck, reuse lint
sh scripts/test-floor.sh  # the tests that load on Plasma 6.0, which CI runs on Fedora 40
sh scripts/gallery.sh     # renders every view to /tmp/ringside-gallery.png
sh scripts/pictures.sh    # renders the README's pictures in docs/ from sample readings
```

Apart from `scripts/test-floor.sh`, they need a Plasma 6.5 or later desktop
(older libplasma ships no importable `org.kde.plasma.plasmoid` module): the Qt 6 `qmllint`/`qmltestrunner`/`qml` tools
(looked for in `/usr/lib/qt6/bin` and `/usr/lib64/qt6/bin`, or set `QMLLINT`,
`QMLTESTRUNNER`, `QML`), the Plasma and libksysguard QML modules, and
Python 3.11+. `scripts/test.sh` also runs `shellcheck` and `reuse lint` when
they're installed, and prints a note when it skips one. `scripts/pictures.sh`
also needs Python's Pillow. `scripts/test-floor.sh` runs from Plasma 6.0 on
and counts a test that fails for want of `org.kde.plasma.plasmoid` as skipped.

## Branches

Work on a branch. Nothing lands on `main` without the owner's go-ahead, and
it lands as one squashed commit; `main` is what people install from and what
releases are tagged on.

When bumping the widget version in `package/metadata.json`, update `VERSION`
in `package/contents/code/usage.py` too. The helper sends it in its HTTP
User-Agent, and the Python tests check that the versions agree.

## Style

- Numbers go through `code/format.js` (locale digits, binary units);
  user-visible strings through `i18nc` in QML, since `.pragma library` files
  can't call it. Colours come from `Kirigami.Theme`, never hardcoded.
- Compatibility floor: Plasma 6.0, Qt 6.6, KDE Frameworks 6.0. No new runtime
  dependencies.
- Comments explain intent in plain sentences; match the surrounding code
  rather than restating it.

## Where to start

`AGENTS.md` maps the repository. `package/contents/ui/main.qml` hosts both
layouts; `Monitor.qml` is the only place that subscribes to ksystemstats.
Tests live under `tests/qml` (QtTest), `tests/helper` (the sh helper's
fixtures) and `tests/python` (the Python helper's tests).
