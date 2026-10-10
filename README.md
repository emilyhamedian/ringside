<p align="center">
  <img src="docs/logo.svg" alt="Ringside" width="300">
</p>

<p align="center">
  <a href="https://github.com/emilyhamedian/ringside/actions/workflows/test.yml"><img src="https://github.com/emilyhamedian/ringside/actions/workflows/test.yml/badge.svg?branch=main" alt="Tests"></a>
  <a href="https://github.com/emilyhamedian/ringside/releases/latest"><img src="https://img.shields.io/github/v/release/emilyhamedian/ringside" alt="Release"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/emilyhamedian/ringside" alt="License: GPL-3.0-or-later"></a>
</p>

Ringside puts your system in your KDE Plasma 6 panel as a row of rings: CPU,
GPU, memory, network and disk. If you use Claude or Codex, it can show your
usage limits too.

![Ringside in a panel: CPU, GPU and memory rings with their names inside, each with its usage over its temperature or the memory in use, a Claude ring with its weekly usage over the days to its reset and its Fable limit in amber on the inner ring, then network rates](docs/panel.png)

- See your CPU, GPU and memory at a glance, with their temperatures right
  beside them.
- Keep an eye on network and disk activity.
- Track your Claude and Codex limits: how much of the week you've used, when
  it resets, and whether you're on pace to run out. These stay off until you
  turn them on.
- Click any item for a popup with graphs of the last minute, hour or day, top
  processes and more.
- It matches your Plasma theme and shows sizes in the units you chose in
  *Region & Language*. Rings turn amber, then red, when something runs hot
  or fills up.

![The CPU, GPU, memory, network and disk popups](docs/popups.png)

## Install

Grab `ringside.plasmoid` from the
[latest release](https://github.com/emilyhamedian/ringside/releases/latest).
You can install it from *Add or Manage Widgets… → Get New… → Install Widget
From Local File…*, or from a terminal:

```bash
kpackagetool6 --type Plasma/Applet --install ringside.plasmoid
```

Then add **Ringside** to a panel like any other widget.

To update to a new release, run the same command with `--upgrade` instead of
`--install`, then restart Plasma by logging out and back in, or with
`systemctl --user restart plasma-plasmashell`. To uninstall, remove it from
your panel and run:

```bash
kpackagetool6 --type Plasma/Applet --remove dev.emily.ringside
```

Building from source? Clone the repository and run `scripts/install.sh`.

### Requirements

You'll need KDE Plasma 6.0 or later, with ksystemstats and libksysguard, which
come with Plasma's System Monitor. A few extras need a little more:

- Memory pressure needs Plasma 6.2 or later.
- Intel GPUs need Plasma 6.4 or later with the i915 driver, or 6.8 or later
  with xe, and don't report a temperature or VRAM.
- Claude and Codex need Python 3.11 or later.
- Keeping graph history across restarts needs Qt's LocalStorage module,
  packaged as `qml6-module-qtquick-localstorage` on Debian and Ubuntu.

## Claude and Codex

![The Claude popup: the weekly limit, the Fable limit in amber with a sentence saying when it is on pace to run out, and a graph of this week's usage with a dashed amber line at the time the Fable limit runs out](docs/usage.png)

Turn them on in *Configure Ringside… → Panel Items*.

- **Claude** needs [Claude Code](https://docs.claude.com/en/docs/claude-code)
  signed in with a subscription. Ringside uses its login to ask Anthropic for
  your limits, and renews it the same way Claude Code does, so you stay
  signed in.
- **Codex** needs the [Codex CLI](https://github.com/openai/codex) signed in,
  and Ringside asks it for your limits.

The ring shows how much of your weekly limit you've used and how long until
it resets. If your plan also has a per-model limit, that shows on an inner
ring. When a check fails, the ring greys out, and if it keeps failing, it's
struck through; the popup tells you why. If Plasma can't find `claude` or
`codex`, you can tell it where they are under *AI Providers*.

**Starting the next session.** A Claude five-hour session or Codex week only
begins when you next send a message. With the switch at the bottom of the
popup turned on, Ringside starts the next one for you as soon as the last one
ends, so the clock is already running by the time you're back. It does this by
sending a short message, which counts toward your limits like any other, so if
you pay for usage beyond your plan, you'll probably want to leave it off.

## Privacy

Ringside doesn't talk to anything outside your computer unless you turn on a
feature that needs to.

- Your system readings come from ksystemstats, the service behind Plasma's
  System Monitor, and from a small script,
  [`ringside-info.sh`](package/contents/code/ringside-info.sh), that reads
  `/proc`, `/sys` and udev as you.
- When you turn on Claude or Codex, Ringside runs
  [`usage.py`](package/contents/code/usage.py). It sends your Claude Code
  login only to Anthropic (`api.anthropic.com`, and `platform.claude.com` to
  renew it), asks the Codex CLI on your computer about Codex, and keeps the
  readings in `~/.cache/ringside/`.
- The public address, off until you turn it on under *General*, shows the
  address websites see in the network popup. To find it, Ringside asks
  [ipify.org](https://www.ipify.org), Mullvad's connection check (which can
  also tell you the city) or a service you choose, only while the popup is
  open and no more than once a minute. The answer is never saved.
- Graph history stays in memory unless you choose to keep it across
  restarts. It's then saved under
  `~/.local/share/plasmashell/QML/OfflineStorage/Databases/`, and turning the
  setting off deletes it again.

## When something looks wrong

Ringside notes what went wrong in Plasma's journal, without tokens, addresses
or account details. To see today's notes:

```bash
journalctl --user --since today QT_CATEGORY=ringside.usage QT_CATEGORY=ringside.network QT_CATEGORY=ringside.gpu QT_CATEGORY=ringside.setup
```

For more detail, including every check and how long it took, add the rule
`ringside.*.debug=true` in KDE's Debug Settings (`kdebugsettings`) and
restart Plasma.

## Contributing

Want to help? [CONTRIBUTING.md](CONTRIBUTING.md) covers the tests, the Plasma
6.0 checks and the code style.

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
