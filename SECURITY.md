# Security

Found a security problem? Please report it privately through [GitHub's
vulnerability reporting][report], not in a public issue. Fixes go into the
latest release.

[report]: https://github.com/emilyhamedian/ringside/security/advisories/new

## What's worth a look

Most of Ringside just draws what Plasma already knows. The parts that do more
are the two helper scripts it runs as you:

- [`usage.py`](package/contents/code/usage.py) runs the Claude and Codex
  items. It reads Claude Code's login to ask Anthropic for your limits, and
  when the login expires it renews it and saves it back the way Claude Code
  does. For Codex it asks the Codex CLI and reads the CLI's login file to
  keep cached balances with the right login.
- [`ringside-info.sh`](package/contents/code/ringside-info.sh) reads `/proc`,
  `/sys` and udev. While the network popup shows your public address, it
  also runs `ip route get` every 3 seconds to see which interface you're
  going out through. That only looks at the routing table; it sends
  nothing.

With the session starter on, `usage.py` also runs the `claude` or `codex` CLI
to send one word. They run in an empty folder of their own,
`~/.local/state/ringside/work`, with a trimmed-down environment, so API keys
and provider overrides from your session aren't passed on.

If you set a program under *AI Providers*, Ringside runs whatever is at that
path as you. It only checks that it's an executable file.

## What leaves your computer

Nothing, until you turn on something that needs it.

- **Claude** sends your Claude Code login only to Anthropic:
  `api.anthropic.com`, and `platform.claude.com` to renew it. Each result,
  errors included, is reused for five minutes by every Ringside widget. If
  Anthropic asks Ringside to back off, it waits at least as long as asked.
- **Codex** only talks to `codex app-server` on your computer, which reaches
  OpenAI with the Codex CLI's own login.
- **Remaining credits** are collected automatically for enabled providers.
  Claude asks `api.anthropic.com` for its organization's prepaid balance
  during usage checks, at most once every five minutes across all Ringside
  widgets. Failed attempts count too. The request uses the existing login
  and does not renew it solely for credits. A rate limit holds both Claude
  reads back, honoring any longer wait Anthropic requests. Codex credits
  come from its existing usage response, with no extra request.
  Neither balance check sends a model request or starts a session. *Show
  remaining credits* is off by default for each provider and only controls
  whether its row appears; hiding it does not stop balance collection.
- **The session starter** sends "Hi" through the Claude Code or Codex CLI
  when a session or week ends. It counts against your limits like any other
  message. To pick Codex's model it reads `~/.codex/models_cache.json`.
- **The public address** asks one service, the one you pick: ipify.org
  (`api.ipify.org` and `api6.ipify.org`), Mullvad (`ipv4.am.i.mullvad.net`
  and `ipv6.am.i.mullvad.net`), or URLs you set. It asks when the network
  popup opens, at most once a minute, again if your route changes while the
  popup is open, and right away when you press *Try again*. Never while the
  popup is closed or you're offline.

  The request carries `User-Agent: ringside/<version>` and
  `Accept-Language: *`, nothing else about you. The service sees your
  address, like any website does. Ringside reads only the address, plus
  `city` and `country` from a JSON reply, keeps the answer in memory only,
  and ignores any reply over 16 KB or one that didn't come over HTTPS from
  the host it asked.

  A few things Qt does that Ringside can't change: it follows redirects,
  even to plain http, before Ringside gets to check them; it keeps any
  cookie the service sets until Plasma restarts; and it keeps reading a
  reply that never ends until Plasma restarts.

## What stays on your computer

- **Claude and Codex readings** are kept in `~/.cache/ringside/`. The same
  private cache keeps each balance, when it was read, when it may be checked
  again, and the identity needed to keep it with the right login. It does
  not keep credentials. Failed balance reads preserve the last successful
  value; a new zero or disabled result clears it. Hiding the rows keeps the
  cache available for when they are shown again or another widget uses it.
- **Graph history** stays in memory, unless you turn on *Keep the last hour
  and day across restarts* under General. Then each widget saves the
  average and peak of every graph for each 30-second and 10-minute step,
  about 100 KB, in a SQLite database Qt keeps in
  `~/.local/share/plasmashell/QML/OfflineStorage/Databases/`, shared by all
  Ringside widgets. Turning the setting off deletes that widget's history;
  removing the widget while it's on doesn't. To clear it all, delete the
  database and the `.ini` beside it that names it `ringside` while Plasma
  isn't running.
- **The journal** gets what goes wrong: failed checks and why, the Anthropic
  host or address service involved, the session starter's steps, a weekly
  limit that resets early, a discrete GPU sleeping or waking, and sensors
  that don't answer. Never tokens, addresses, places, account names or file
  contents. Program paths show your home folder as `~`. Anyone who can read
  your journal can read these: you, administrators, and groups such as
  `systemd-journal`.
