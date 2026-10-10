# Contributing

## Checks

```bash
sh scripts/test.sh        # the linters and the QML, sh and Python tests
sh scripts/test-floor.sh  # the tests and the gallery on Plasma 6.0
sh scripts/gallery.sh     # renders every view to /tmp/ringside-gallery.png
sh scripts/pictures.sh    # renders the README's pictures in docs/
python3 scripts/logo.py   # draws the logo in docs/ and the widget's icon
sh scripts/package.sh     # builds ringside.plasmoid from the last commit
```

`scripts/test.sh`, `scripts/gallery.sh` and `scripts/pictures.sh` need a
Plasma 6.5 or later desktop, since older libplasma ships no importable
`org.kde.plasma.plasmoid` module: the Qt 6 `qmllint`, `qmltestrunner` and
`qml` tools (looked for in `/usr/lib/qt6/bin` and `/usr/lib64/qt6/bin`, or
set `QMLLINT`, `QMLTESTRUNNER`, `QML`), the Plasma and libksysguard QML
modules, and Python 3.11+. `scripts/test.sh` also runs `shellcheck` and
`reuse lint` when they're installed, and prints a note when it skips one.
`scripts/test-floor.sh` runs from Plasma 6.0 on, with a stand-in for
`org.kde.plasma.plasmoid` from `tests/floor` on the import path.
`scripts/pictures.sh` also needs Pillow, and `scripts/logo.py` fontTools,
Nunito and `rsvg-convert`.

CI runs the full suite and the gallery on Fedora 44, and the floor tests on
Fedora 40 as released. Pushes to development branches (`fix/`, `feat/`,
`docs/` and the like) that change only the docs run REUSE lint alone, and
draft PRs to main wait until they're marked ready. The rules and their
tests are in `.github/scripts/`.

## Branches

Work on a branch. Nothing lands on `main` without the owner's go-ahead, and
it lands as one squashed commit; `main` is what people install from and what
releases are tagged on.

When bumping the widget version in `package/metadata.json`, update `VERSION`
in `package/contents/code/usage.py` too. The helper sends it in its HTTP
User-Agent, and the Python tests check that the versions agree.

## Style

[AGENTS.md](AGENTS.md) sets the project's rules and maps the repository.
Two more:

- Journal lines go through `ui/code/log.js` under a `ringside.<area>`
  LoggingCategory (usage, network, gpu, setup). The helper's lines come
  from the fixed templates in `usage.py`'s `MESSAGES`, so no token,
  address, account or reply text can reach them; keep it that way, and keep
  the privacy tests in `tests/python/test_journal.py` covering any new
  input. Turn debug on with `QT_LOGGING_RULES="ringside.*.debug=true"`.
- Tests map points with `mapToItem(item, Qt.point(x, y))`: Qt 6.6 truncates
  the separate x and y of `mapToItem(item, x, y)` to whole numbers.
