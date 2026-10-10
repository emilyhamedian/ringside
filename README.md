<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/logo-dark.svg">
    <img src="docs/logo.svg" alt="Ringside" width="300">
  </picture>
</p>

<p align="center">
  <a href="https://github.com/emilyhamedian/ringside/actions/workflows/test.yml"><img src="https://github.com/emilyhamedian/ringside/actions/workflows/test.yml/badge.svg?branch=main" alt="Tests"></a>
  <a href="https://github.com/emilyhamedian/ringside/releases/latest"><img src="https://img.shields.io/github/v/release/emilyhamedian/ringside" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/emilyhamedian/ringside" alt="License: GPL-3.0-or-later"></a>
</p>

System monitor rings for your KDE Plasma 6 panel: CPU, GPU, memory, network
and disk, plus your Claude and Codex usage limits if you want them.

![Ringside in a panel: CPU, GPU and memory rings with their names inside, each with its usage over its temperature or the memory in use, a Claude ring with its weekly usage over the days to its reset and its Fable limit in amber on the inner ring, then network rates](docs/panel.png)

- **CPU, GPU and memory** at a glance, as rings with their temperatures
  beside them.
- **Network and disk** activity.
- **Claude and Codex** limits: how much of the week you've used, when it
  resets, and whether you're on pace. Off by default.
- **A popup for every item**, with graphs of the last minute, hour or day,
  top processes and more.
- Follows your Plasma theme, and turns amber, then red, as things run hot or
  fill up.

![The CPU, GPU, memory, network and disk popups](docs/popups.png)

## Install

Download `ringside.plasmoid` from the
[latest release](https://github.com/emilyhamedian/ringside/releases/latest)
and install it from *Add or Manage Widgets… → Get New… → Install Widget From
Local File…*, or:

```bash
kpackagetool6 --type Plasma/Applet --install ringside.plasmoid
```

Then add **Ringside** to a panel. To update, use `--upgrade` instead of
`--install` and restart Plasma (log out and in, or
`systemctl --user restart plasma-plasmashell`). To uninstall:

```bash
kpackagetool6 --type Plasma/Applet --remove dev.emily.ringside
```

From source: clone the repository and run `scripts/install.sh`.

### Requirements

- KDE Plasma 6.0 or later, with ksystemstats and libksysguard (they come with
  Plasma's System Monitor).
- Memory pressure needs Plasma 6.2. Intel GPUs need 6.4 with i915 or 6.8 with
  xe, and report no temperature or VRAM.
- Claude and Codex need Python 3.11 or later.
- Keeping graph history across restarts needs Qt's LocalStorage module
  (`qml6-module-qtquick-localstorage` on Debian and Ubuntu).

## Claude and Codex

![The Claude popup: the weekly limit, the Fable limit in amber with a sentence saying when it is on pace to run out, and a graph of this week's usage with a dashed amber line at the time the Fable limit runs out](docs/usage.png)

Turn them on under *Configure Ringside… → Panel Items*.

- **Claude** needs [Claude Code](https://docs.claude.com/en/docs/claude-code)
  signed in with a subscription. Ringside reads its login and asks Anthropic
  for your limits, renewing the login the way Claude Code does so it stays
  signed in.
- **Codex** needs the [Codex CLI](https://github.com/openai/codex) signed in.
  Ringside asks it for your limits.

The ring shows the weekly limit and the time to its reset; an inner ring shows
a per-model limit if your plan has one. If a check fails, the ring greys out,
then is struck through, and the popup says why. If Plasma can't find `claude`
or `codex`, set where it is under *AI Providers*.

**Starting the next session.** A switch at the bottom of each popup, off by
default, starts your next Claude five-hour session or Codex week as soon as
the last one ends, by sending one tiny message ("Hi" on Claude's smallest
model, or one read-only Codex turn). Each message counts toward your limits
like any other. If you pay for usage beyond your plan, leave it off: Ringside
doesn't check whether a message would be billed.

## Privacy

A fresh install contacts nothing beyond your machine.

- **System readings** come from ksystemstats, plus
  [`ringside-info.sh`](package/contents/code/ringside-info.sh), which reads
  `/proc`, `/sys` and udev as your user.
- **Claude and Codex**, when you turn them on, run
  [`usage.py`](package/contents/code/usage.py). It sends your Claude Code
  login only to Anthropic (`api.anthropic.com`, and `platform.claude.com` to
  renew it), asks the Codex CLI on your machine for Codex, and keeps the
  readings in `~/.cache/ringside/`.
- **Public address**, off until you turn it on under *General*, shows the
  address websites see in the network popup. Ringside asks
  [ipify.org](https://www.ipify.org), Mullvad's connection check (which also
  names a city) or a service you set, only while the popup is open and at most
  once a minute. The answer stays in memory.
- **Graph history** stays in memory unless you turn on keeping it across
  restarts; it is then saved under
  `~/.local/share/plasmashell/QML/OfflineStorage/Databases/`. Turning the
  setting off deletes it.

## When something looks wrong

Ringside writes failures to Plasma's journal, never with tokens, addresses or
account details:

```bash
journalctl --user --since today QT_CATEGORY=ringside.usage QT_CATEGORY=ringside.network QT_CATEGORY=ringside.gpu QT_CATEGORY=ringside.setup
```

For every check with its timing, add the rule `ringside.*.debug=true` in
KDE's Debug Settings (`kdebugsettings`) and restart Plasma.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the tests, the Plasma 6.0 checks
and the style.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
