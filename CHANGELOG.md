# Changelog

All notable changes to Ringside are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.3.0] - 2026-10-05

### Added

- The Claude and Codex popup says where the week is heading in one
  sentence, at the rate it has been used so far, such as "On pace to use
  80% by the reset", "Fable is on pace to run out Tue 3:30 AM" or "Limit
  reached Sun 3:00 PM". It appears from a day into the week, or at once for
  a limit that is running out. Colours still follow the reading alone:
  amber from 75% and red from 90%.
- The week graph in the Claude and Codex popup has a line at 100%, a floor
  with a tick at each midnight, and an edge at the reset. For the limit the
  pace sentence says runs out, a dashed line in that limit's colour marks
  the moment, with the time under the floor. A single reading shows as a
  dot, and the marker for now appears only when the last reading is over
  two hours old.
- A failed Claude or Codex check shows a small amber dot at the ring's
  corner, and the tooltip says when it failed, even with the ring's text
  shown. This replaces the fade, which looked like a sleeping GPU.
- A panel item with keyboard focus has a line around it in the theme's
  focus colour.
- A switch in the Claude and Codex popups, off by default, starts the next
  Claude session or Codex week as soon as the last one ends, by sending one
  word through the Claude Code or Codex CLI, so a window is always running
  instead of waiting for your next message. The line under the switch says
  when the next one starts, or why it can't. See "Starting the next session"
  in the README.
- Readings move into place instead of jumping. A ring sweeps to each new
  reading and turns amber or red as it passes 75% or 90%, and the number in
  a popup's ring counts along with it; the Claude and Codex bars do the
  same. The week graph draws each new stretch of line and fades in its
  run-out, and a second GPU's ring and its popup section fade in and out.
  The motion follows Plasma's animation
  speed, and with animations set to Instant readings change at once, as
  before.

### Changed

- Across a horizontal panel, rates always show three figures, from kb/s or
  KiB/s up, such as "8.40 Mb/s", "62.1 kb/s", or "0.00 KiB/s" when idle,
  and move to the next unit before a fourth: 1023 KiB/s reads "1.00 MiB/s".
  A rate's unit sits closer to its number. Memory in use shows three
  figures too, such as "9.60G". Tooltips and popups keep their own formats.
- Panel items sit a little further apart, half as much again as the gap
  between a ring and its readings, so each item's readings read as its own
  ring's.
- The panel countdown shows only its largest unit: "6d", "23h" or "59m";
  the popup and the tooltip keep the full time. It turns red at 100%, where
  it says how long the limit stays reached.
- Top processes show a busy indicator until they are read, in the popup's
  dim text colour like its captions rather than the theme's accent. The CPU
  list, which needs two scans, fills in about two seconds after its popup
  opens, where it could take four.
- Popup numbers and the ring's centre percentage use the theme's font with
  figures of even width instead of a monospace font, which left gaps around
  the decimal point. Units are smaller. °C and °F sit close to the digits:
  raised level with their top in the CPU and GPU headers, on the same line
  in the disk's caption. Process names stay monospace.
- Graphs lose their grid lines. Percentage graphs have a line at 100%,
  named at the end of the caption line above the graph, where no line can
  cross it; rate graphs reach up to their peak, named in the same place when
  it fits, or to 1 Mb/s (1 MiB/s for a disk) when the peak is lower, and the
  disk's peaks move into its captions.
- The popups' graphs take a reading every second, or at the update interval
  when that is shorter, so they catch short bursts: 60 points a minute at
  the default interval and up. Each new reading moves the line a step to
  the left at once. The panel still changes once per update interval, and
  a popup's readings follow each one, so its numbers agree with the graph
  under them.
- Temperature sensors have plain names: chip, chiplet, hotspot and memory
  instead of Tctl, Tccd, junction and mem.
- The Claude and Codex popup sets its countdown's units smaller than its
  digits; the panel's stay the size of its digits. With one limit it shows
  no bars, since the ring gives the number, and reads "Weekly limit". The
  week graph loses its day lines, half line and even-pace diagonal;
  midnights are short ticks on its floor.
- Popups line up their content on one edge and their headers on shared
  baselines, with even padding in tiles and matching dividers. The load
  average shows its three numbers evenly spaced, the network header's
  rates are larger, and "Since boot" puts each arrow before its total. The
  footer's link and settings button line up with the edges of the readings
  above them. The network header gives the connection's name and its
  address a line each, so a long name no longer hides the address.
- Each GPU in the GPU popup opens with the header the CPU and Claude popups
  use: its usage ring, its name, its kind and memory, and its temperature.
  A second GPU follows after a rule with a header of its own, and a
  sleeping GPU stays one line.
- Translators are told that CPU, GPU and MEM sit inside a ring in at most
  three characters.
- The Codex ring shows the Codex mark, its cloud drawn as an outline, instead
  of the OpenAI logo.

### Removed

- The Standalone layout, with its Layout and Fold settings and
  `scripts/add-panel.sh`. A panel set up for it now shows the strip; remove
  that panel and add Ringside to another one if you'd rather.
- The Claude helper's fallback that took a Fable limit from a separate
  field of Anthropic's reply. Model limits now come only from the reply's
  list of limits, under the names it gives them.

### Fixed

- Ring names and the Claude and Codex marks sit at the ring's centre. At
  scales such as 125% they could be up to a pixel off: a ring of an odd
  size was rounded to a whole pixel, the marks were snapped to the
  screen's pixels, and names were centred with the space below their
  letters and after the last one.
- With a right-to-left language, panel rates keep each number before its
  unit, and the load average no longer has a dot that reads as an Arabic
  zero.
- A longer translation of the Memory popup's legend wraps instead of
  widening the popup past its frame.
- Screen readers say "unavailable" for a missing rate or load average
  instead of reading out a dash and a stray unit.
- Claude and Codex times, such as when the week resets or when a check
  failed, no longer show seconds in the C locale on Qt 6.6.
- A top process that runs several times shows its count in the locale's
  digits, and popup percentages follow the translation's percent format.

## [0.2.2] - 2026-10-04

### Changed

- Each ring carries its item's name inside it: CPU, GPU and MEM, or the
  Claude or Codex mark. Beside it, the ring's percentage sits over its
  temperature, the memory in use or the time to the weekly reset, in the
  theme's own font with figures of even width.
- Rings fill the panel's thickness, with a lighter stroke, and the hover
  highlight leaves a thinner margin above and below.
- A ring's percentage turns amber and red with the ring; the time to a reset
  stays dim.
- Network and disk rates sit on the same two lines as the rings' readings,
  with no divider before them. On a thin panel the readings share one line,
  "23% · 61°".
- The inner ring's GPU, normally the integrated one, keeps its usage on the
  ring; its temperature moves from the panel to the GPU popup.
- Standalone dials show the same two lines under the ring. Claude and Codex
  show the time to the reset there instead of the per-model limit, which
  stays on the inner ring. A horizontal Standalone panel grows to fit the
  second line, and a vertical one keeps room either side of its widest
  dial, so readings in a larger font aren't clipped at its edges.

### Removed

- The Ring size setting: rings follow the panel's thickness.

### Fixed

- GPU power polling reuses command names instead of accumulating QML
  properties that make Plasma progressively slower during long sessions.
  Cached replies are discarded and slow replies retain their request time.
- The Plasma 6.0 CI job uses Fedora's download server for its archived
  packages and retains download diagnostics. The usage helper reports the
  widget's version.
- A Standalone dial's time to a reset is current as soon as the panel
  unfolds.
- The Claude and Codex marks follow the theme's text colour instead of
  staying white on a light panel.
- Removing a widget no longer can log a script error from its GPU power
  polling.
- Moving a Standalone panel between a side edge and the top or bottom no
  longer logs a binding loop on Plasma 6.0.

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

[Unreleased]: https://github.com/emilyhamedian/ringside/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/emilyhamedian/ringside/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/emilyhamedian/ringside/compare/v0.2.0...v0.2.2
[0.2.0]: https://github.com/emilyhamedian/ringside/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/emilyhamedian/ringside/releases/tag/v0.1.0
