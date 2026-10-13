# Changelog

All notable changes to Ringside are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project
follows [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- *Panel space*, under Panel Items, lets Ringside fill the panel's free
  space with its items at the start, middle or end, so it can keep to the
  far end of the panel without a spacer widget beside it. It's off by
  default.

## [0.3.1] - 2026-10-11

### Added

- When a Claude or Codex weekly limit resets before it was due, the popup
  says "You got an early reset" and how much of the limit you got back. It
  shows for a day, or until you've opened the popup once. Ringside also
  notices a reset that came while Plasma wasn't running, if the week it cut
  short hadn't ended and you haven't used as much again since.

### Fixed

- After an early reset, the session starter no longer shows the old week's
  times or waits for the old reset before starting your next session or
  week.
- After a weekly limit is cleared early without its reset time moving, the
  pace sentence and the week graph's run-out count from the reset rather
  than from the start of the week, so they no longer understate how fast
  you're using it.

## [0.3.0] - 2026-10-10

### Added

- Graphs can show the last minute, hour or day. Click the span in any
  graph's caption to pick one; it applies to every graph and is remembered.
  Time the computer was asleep or Plasma wasn't running shows as a gap.
- *Keep the last hour and day across restarts*, under General, saves graph
  history between restarts. It's off by default. On Debian and Ubuntu it
  needs `qml6-module-qtquick-localstorage`. SECURITY.md says what's kept and
  where.
- The CPU, GPU and disk popups graph temperature too, with your hot
  threshold marked and the line turning amber and red as it crosses your
  thresholds.
- The network popup can show your public address, the one websites see,
  with the interface it leaves through, a shield for a VPN, and a warning
  when IPv4 and IPv6 take different routes. It's off by default. It asks
  ipify.org, Mullvad (which can also name the city) or a service you set,
  and only while the popup is open.
- The Claude and Codex popup tells you where your week is heading, such as
  "On pace to use 80% by the reset" or "Fable is on pace to run out Tue 3:30
  AM". If a limit is on pace to run out, the week graph marks when.
- When a Claude or Codex check fails, the ring keeps its last reading in
  grey and breaks into segments. If it keeps failing, the ring is struck
  through. The tooltip and popup say what went wrong and when Ringside will
  try again.
- Claude and Codex show up as soon as the widget starts, with a ring of dots
  while the first check runs.
- A switch in the Claude and Codex popups, off by default, starts your next
  Claude session or Codex week as soon as the last one ends, by sending one
  word. See "Starting the next session" in the README.
- Readings slide into place instead of jumping, at Plasma's animation speed.
- A logo, which is also the widget's icon.
- Ringside writes what goes wrong to Plasma's journal, so you can find out
  later why a ring greyed out. It never writes tokens, addresses, places or
  account names. See "When something looks wrong" in the README.
- If Plasma can't find `claude` or `codex`, as with an npm, bun or nvm
  install, you can tell it where they are under *AI Providers*.
- A panel item with keyboard focus has a line around it.

### Changed

- Rings are gently shaded, lighter at the top and deeper at the bottom.
- Claude checks wait up to 20 seconds, like Codex checks, so a slow
  connection greys the ring less often.
- Panel numbers keep a steady width: rates always show three figures, such
  as "8.40 Mb/s", and memory shows one decimal, such as "9.6 GiB".
- The panel countdown shows just its largest unit, such as "6d", and stays
  plain. The ring and the percentage carry the colour.
- Popups are cleaner: numbers in your theme's font, no grid lines, and
  everything lined up on one edge.
- Graphs take a reading every second, so they catch short bursts.
- Network and disk each have a popup of their own.
- The GPU popup gives each GPU its own header, with the integrated one
  first.
- The network graph draws upload as clearly as download, with longer
  dashes.
- CPU and GPU temperatures name their sensor in plain words, like
  "hotspot", and only when it isn't the whole chip.
- Top processes fill in sooner when you open the CPU popup.
- The Codex ring can show the Codex mark or the OpenAI logo. With the OpenAI
  logo it's called ChatGPT.
- Claude and Codex settings moved to a new *AI Providers* page. Your
  settings carry over.
- Sizes follow your choice in *Region & Language → Data and storage units*:
  GiB, GB, or 1000-based GB.

### Removed

- The Graph history setting. The span on each graph replaces it.
- The Standalone layout. A panel that used it now shows the regular strip.
- Reading Claude's Fable limit from a separate part of Anthropic's reply.
  Per-model limits now come only from its list of limits.

### Fixed

- The GPU popup's temperature graph no longer goes missing at an hour or a
  day.
- Screen readers read percentages in your language's digits, and say
  "unavailable" instead of reading out a dash.
- Codex no longer disappears for five minutes after an unrelated error.
- Ring names and marks sit exactly in the middle at scales like 125%.
- In right-to-left languages, panel numbers stay before their units, and
  the load average no longer has a dot that reads as an Arabic zero.
- A long translation of the memory legend wraps instead of stretching the
  popup.
- Times no longer show seconds in the C locale on Qt 6.6.
- Process counts and percentages follow your language's digits and percent
  format.
- Opening the settings no longer fills the journal with warnings.
- With animations set to Instant, a ring near its limit no longer pulses,
  and a new week shows at once.

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

[Unreleased]: https://github.com/emilyhamedian/ringside/compare/v0.3.1...HEAD
[0.3.1]: https://github.com/emilyhamedian/ringside/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/emilyhamedian/ringside/compare/v0.2.2...v0.3.0
[0.2.2]: https://github.com/emilyhamedian/ringside/compare/v0.2.0...v0.2.2
[0.2.0]: https://github.com/emilyhamedian/ringside/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/emilyhamedian/ringside/releases/tag/v0.1.0
