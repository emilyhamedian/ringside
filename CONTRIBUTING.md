# Contributing

## Checks

```bash
sh scripts/test.sh        # qmllint, the QML tests, the helpers' tests, shellcheck, reuse lint
sh scripts/test-floor.sh  # the tests and the gallery on Plasma 6.0, which CI runs on Fedora 40
sh scripts/gallery.sh     # renders every view to /tmp/ringside-gallery.png
sh scripts/pictures.sh    # renders the README's pictures in docs/ from sample readings; needs Pillow
python3 scripts/logo.py   # draws the logo in docs/ and the widget's icon; needs fontTools, Nunito and rsvg-convert
sh scripts/package.sh     # builds ringside.plasmoid from the last commit
```

Apart from `scripts/test-floor.sh`, they need a Plasma 6.5 or later desktop
(older libplasma ships no importable `org.kde.plasma.plasmoid` module): the Qt 6 `qmllint`/`qmltestrunner`/`qml` tools
(looked for in `/usr/lib/qt6/bin` and `/usr/lib64/qt6/bin`, or set `QMLLINT`,
`QMLTESTRUNNER`, `QML`), the Plasma and libksysguard QML modules, and
Python 3.11+. `scripts/test.sh` also runs `shellcheck` and `reuse lint` when
they're installed, and prints a note when it skips one. `scripts/test-floor.sh`
runs from Plasma 6.0 on, with a stand-in for `org.kde.plasma.plasmoid` from
`tests/floor` on the import path.

CI runs the full suite and gallery on Fedora 44 and the compatibility tests
on Fedora 40 as released. Main, tags and release branches always run both.
On development branches (`codex/`, `fix/`, `feat/`, `feature/`, `docs/`, `ci/`),
changes limited to this file, README, CHANGELOG and the three existing images
in `docs/` run REUSE lint and retain the `test` and `floor` checks. Workflows,
agent instructions, security guidance and all other paths run the full tests.
Push coverage uses the whole branch since its merge base with main, so a
docs push cannot hide code from a cancelled run. PR coverage uses the merge
commit's diff against its base.
An exact commit with a mergeable, open PR from the same repository to main
and a matching PR workflow keeps the PR merge checks and skips duplicate
development push jobs. That workflow must have classified the PR's current
merge commit successfully. Branches still run when that evidence is absent
or unavailable. Draft PRs to main defer the Fedora jobs, as do exact matching
development pushes while their same-repository PR is a draft. Draft classification cannot
stand in for a tested merge commit. Marking a PR ready runs both full suites,
even for docs-only changes, and subsequent ready PR updates run them again.
Returning a development PR to draft cancels its superseded PR run.
Superseded development runs are cancelled within each event type; pushes
cannot cancel PR merge tests. PRs targeting a release branch run in full.

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
- Journal lines go through `ui/code/log.js` under a `ringside.<area>`
  LoggingCategory (usage, network, gpu, setup) at info by default: warnings
  and info for failures and changes, debug for each check. The helper's lines
  come from the fixed templates in `usage.py`'s `MESSAGES`, so no token,
  address, account or reply text can reach them; keep it that way, and keep
  the privacy tests in `tests/python/test_journal.py` covering any new
  input. Turn debug on with `QT_LOGGING_RULES="ringside.*.debug=true"`.
- Tests map points with `mapToItem(item, Qt.point(x, y))`: Qt 6.6 truncates
  the separate x and y of `mapToItem(item, x, y)` to whole numbers.

## Where to start

`AGENTS.md` maps the repository. `package/contents/ui/main.qml` hosts the
panel strip and the popup; `Monitor.qml` is the only place that subscribes
to ksystemstats. Tests live under `tests/qml` (QtTest), `tests/helper` (the
sh helper's fixtures) and `tests/python` (the Python helper's tests).
CI coverage rules and their tests live in `.github/scripts/`.
