# Security

Found a security problem? Please report it privately through [GitHub's
vulnerability reporting][report], not in a public issue. Fixes go into the
latest release.

[report]: https://github.com/emilyhamedian/ringside/security/advisories/new

## What's worth a look

Most of Ringside just draws what Plasma already knows. The parts that do more
are the two helper scripts it runs as you:

- [`usage.py`](package/contents/code/usage.py) runs the Claude, Codex, Kimi,
  OpenCode Go and Antigravity items. It reads Claude Code's login to ask Anthropic for your limits,
  and when the login expires it renews it and saves it back the way Claude
  Code does. For Codex it asks the Codex CLI and reads the CLI's login file
  to keep cached balances with the right login. For Kimi it reads, and never
  writes, Kimi Code's settings and sign-in in `~/.kimi-code/` and the Kimi
  Code keys OpenCode keeps in `~/.local/share/opencode/`. For OpenCode Go it
  reads, and never writes or renews, OpenCode's sign-in to the OpenCode
  Console in the same folder. For Antigravity it reads, and never writes
  directly, Antigravity's OAuth token from `~/.gemini/`, the desktop Secret
  Service (via `secret-tool`, when present), Antigravity IDE's `state.vscdb`
  (read-only) or T3 Code's Antigravity provider folder; when a token expires,
  it asks `agy acp --stdio` to renew it without sending any prompt.
- [`ringside-info.sh`](package/contents/code/ringside-info.sh) reads `/proc`,
  `/sys` and udev. While the network popup shows your public address, it
  also runs `ip route get` every 3 seconds to see which interface you're
  going out through. That only looks at the routing table; it sends
  nothing.

With the session starter on, `usage.py` also runs the `claude`, `codex`,
`opencode` or `agy` CLI to send one word. They run in an empty folder of
their own, `~/.local/state/ringside/work`, with a trimmed-down environment,
so API keys and provider overrides from your session aren't passed on.

If you set a program under *AI Providers*, Ringside runs whatever is at that
path as you. It only checks that it's an executable file.

## What leaves your computer

Nothing, until you turn on something that needs it.

- **CLIProxyAPI** reads Claude, Codex, Kimi and Antigravity limits through a
  hub on your computer. Ringside sends the hub's management key only to the
  loopback address you set and trusts the process listening there. It bypasses
  HTTP proxies and disables redirects. If the hub rejects the key during a
  quota check, Ringside waits at least an hour before trying it again.
  Changing the key file clears the wait. The hub sends the account's
  credentials to its provider's usage endpoint. For Codex, it also asks
  `chatgpt.com` for missing banked reset dates. If the answer is incomplete,
  Ringside waits an hour or until the reported resets change. Settings store
  the key file's path. Ringside never downloads the hub's credential files
  or logs management keys or account identities.
- **Claude** sends your Claude Code login only to Anthropic:
  `api.anthropic.com`, and `platform.claude.com` to renew it. Each result,
  errors included, is reused for five minutes by every Ringside widget. If
  Anthropic asks Ringside to back off, it waits at least as long as asked.
  The usage request identifies itself as a Claude Code release
  (`claude-cli/2.1.321`) and asks for banked resets (`?cedar_ember=1`),
  because Anthropic includes them in the reply only for Claude Code. Every
  other request identifies itself as Ringside.
- **Codex** only talks to `codex app-server` on your computer, which reaches
  OpenAI with the Codex CLI's own login.
- **Kimi** sends one Kimi Code credential, the first it finds, only to Kimi:
  `api.kimi.ai`, or `api.kimi.com` for a China account. Only keys for Kimi
  Code's own endpoints are sent; a Moonshot Platform key is never used. Each
  result, errors included, is reused for five minutes by every Ringside
  widget.
- **OpenCode Go** sends OpenCode's Console sign-in and the ID of the
  organisation it belongs to only to `opencode.ai`, and only when that
  sign-in is for opencode.ai's Console. Each result is reused for five
  minutes, as for Kimi.
- **Antigravity** sends your Antigravity sign-in only to Google's Antigravity
  backend (`daily-cloudcode-pa.googleapis.com`). The requests identify
  themselves as Antigravity (`antigravity/2.24.0 linux/amd64`), because the
  endpoint rejects generic clients with HTTP 403 and omits Gemini quota
  buckets for older client versions. When a one-hour access token expires and
  `agy` is installed, Ringside asks `agy acp --stdio` to run `authenticate`
  with `--disable-telemetry` and no prompt so `agy` refreshes its own token.
  Each result is reused for five minutes.
- **Remaining credits** are checked even when hidden. Claude's balance
  needs a request to `api.anthropic.com` and Antigravity's AI Credits balance
  needs a request to `daily-cloudcode-pa.googleapis.com`, each at most once
  every five minutes per account across all widgets, counting failed attempts.
  Ringside uses the current login without renewing it. A rate limit pauses
  both the balance and usage checks for that provider. For hub accounts,
  Ringside reads Claude's profile for the organization ID and reuses it while
  the credential revision stays the same, and asks Google's `loadCodeAssist`
  endpoint for Antigravity's AI Credits. Codex and Kimi return balances with
  their limits. None of these checks sends a model request or starts a
  session.
- **The session starter** sends "Hi" through the Claude Code, Codex, OpenCode
  or Antigravity (`agy`) CLI when a session or week ends. It counts against
  your limits like any other message. It pauses while that provider's readings
  come through the hub, until a fresh direct reading. To pick Codex's model it
  reads `~/.codex/models_cache.json`. For OpenCode Go it asks
  `opencode models` which Go models there are and sends with the cheapest it
  knows, through a private OpenCode server that stops with it; OpenCode keeps
  the message as an archived session titled "Ringside". For Antigravity it
  starts `agy acp --stdio --disable-telemetry` with no MCP servers, reads the
  available models, and sends "Hi" using the cheapest available Gemini and/or
  Claude/GPT model for whichever model pool isn't currently running.
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

- **Claude, Codex, Kimi, OpenCode Go and Antigravity readings** are kept in `~/.cache/ringside/`.
  Claude's and Codex's readings can include the number of banked resets
  and their expiry dates. The same
  private cache keeps each balance, when it was read, when it may be checked
  again, and the identity needed to keep it with the right login. It does
  not keep credentials. It records whether the balance fell since the
  previous successful check for the blue ring; failed reads clear that
  indication. Failed balance reads preserve the last successful
  value; a new zero or disabled result clears it. Hiding the rows keeps the
  cache available for when they are shown again or another widget uses it.
  The private hub cache keeps hashed account IDs, Claude organization IDs,
  banked reset expiries, balances and up to seven days of pooled usage.
- **Graph history** stays in memory, unless you turn on *Keep the last hour
  and day across restarts* under General. Then each widget saves the
  average and peak of every graph for each 30-second and 10-minute step,
  about 100 KB, in a SQLite database Qt keeps in
  `~/.local/share/plasmashell/QML/OfflineStorage/Databases/`, shared by all
  Ringside widgets. Turning the setting off deletes that widget's history;
  removing the widget while it's on doesn't. To clear it all, delete the
  database and the `.ini` beside it that names it `ringside` while Plasma
  isn't running.
- **The journal** gets what goes wrong: failed checks and why, the Anthropic,
  Kimi, OpenCode or Google host or address service involved, the session starter's
  steps, a weekly or monthly limit that resets early, a discrete GPU sleeping
  or waking, and sensors that don't answer. Never tokens, addresses, places, account names or file
  contents. Program paths show your home folder as `~`. Anyone who can read
  your journal can read these: you, administrators, and groups such as
  `systemd-journal`.
