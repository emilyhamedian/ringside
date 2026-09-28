# Changelog

All notable changes to Ringside are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.0] - 2026-09-28

### Added

- Claude Code and Codex weekly-limit items (opt-in), moved over from the
  Usage Rings widget, which Ringside now replaces: a popup showing every
  limit and a graph of the week so far.
- A Standalone layout: the same items as large dials in a panel of their
  own, which folds behind maximized windows, also from Usage Rings.
- Rings turn amber at 75% and red at 90% of their own percentage.

### Changed

- Items sit closer together in the panel.
- A sleeping discrete GPU drops out of the panel until it wakes, as on a
  single-GPU machine.
- Popups spell out °C or °F instead of a bare degree sign.

### Fixed

- Readouts use a fixed-width font on KDE Frameworks older than 6.14, such as
  Debian 13's and Fedora 40's, instead of logging script errors and falling
  back to the default font.
- The CPU popup no longer logs a binding loop on Qt 6.6.
- Ringside no longer logs "Exposed with no visual parent" warnings, or a
  locale warning each time a widget starts.
- An open popup stays on its item when another item comes or goes, and
  closes when its own item goes.
- The Memory popup lists its top processes on Plasma 6.0 to 6.2, and there
  the CPU and Memory popups no longer log a warning for every process.

### Security

- The Claude helper carried over from Usage Rings is hardened against
  losing or leaking the Claude Code login: it checks that it can save a
  renewed login before renewing it, doesn't overwrite one Claude Code
  renewed meanwhile, and keeps request details out of the widget.

## [0.1.0] - 2026-09-27

### Added

- Initial release: CPU, GPU, memory, network and disk as rings and rate
  readouts in the panel, each opening a popup with history graphs,
  per-thread load, top processes, VRAM, clocks, power, swap, memory
  pressure and disk activity.
- Settings pages for update interval, temperature units and thresholds,
  network rate units, panel items and their order, and per-sensor choices
  (CPU temperature source, which GPU goes on which ring, network interface,
  disk and volume).
- A laptop's discrete GPU is read only while something else has woken it,
  and one reader per GPU is shared across widgets so a second Ringside
  doesn't keep it awake.

[Unreleased]: https://github.com/emilyhamedian/ringside/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/emilyhamedian/ringside/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/emilyhamedian/ringside/releases/tag/v0.1.0
