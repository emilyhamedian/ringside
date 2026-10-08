# Security

Report a vulnerability privately through GitHub's
[private vulnerability reporting](https://github.com/emilyhamedian/ringside/security/advisories/new),
rather than a public issue. Fixes go into the latest release.

## Scope

Mainly the two helpers Ringside runs:

- `package/contents/code/usage.py` reads your Claude Code login to poll its
  usage limits and can renew it, saving it back the way Claude Code does. For
  Codex it only checks that `~/.codex/auth.json` exists, then asks the Codex
  CLI.
- With the session starter switched on, `usage.py` also runs the Claude Code
  and Codex CLIs to send one word: `claude auth status` to check the login,
  then `claude -p`, or `codex exec`. They run in an empty private folder,
  `~/.local/state/ringside/work`, with an environment cut down to what they
  need, so API keys and provider overrides in your session are not passed
  on. Before running `claude` it may renew Claude Code's login as polling
  does, holding the same lock, so the two never race on the single-use
  refresh token.
- `package/contents/code/ringside-info.sh` reads `/proc`, `/sys` and udev's
  database as your user. Every 3 seconds while the network popup shows the
  public address it runs `ip route get` and `ip -6 route get` for a fixed public address, a lookup
  in the kernel's routing tables that sends nothing, and reads the type of
  the interface found in `/sys/class/net`.

## What Ringside reads and sends

- System items (CPU, GPU, memory, network, disk) read `/proc`, `/sys`,
  udev's database and ksystemstats, and send nothing.
- Their graphs' history stays in memory unless *Keep the last hour and day
  across restarts* is on under General, which it isn't by default. Then
  each widget saves the average and highest reading of every graph (CPU,
  memory and GPU usage, the temperatures, network and disk rates) for each
  30-second and 10-minute step, every 10 minutes and as the widget stops,
  keyed by the widget's id, with Qt's LocalStorage in one SQLite database
  for all Ringside widgets:
  `~/.local/share/plasmashell/QML/OfflineStorage/Databases/a7cd204c17273ec1e4b4cb45252c93f3.sqlite`,
  with an `.ini` beside it naming it `ringside`. Your user can read it, as
  it can your other Plasma data. Each save drops every widget's steps from
  before the last hour and day, so it holds about a day, about 100 KB a
  widget. Turning the setting off deletes that widget's steps, and leaves
  the files. A widget removed with the setting on leaves its steps: another
  Ringside widget with the setting on drops them at its first save a day
  after the removal, and with none they stay. A widget added meanwhile that
  Plasma gives the same id picks them up, so turn the setting off before
  removing one. To remove them by hand, delete both files while Plasma
  isn't running, which clears every widget's steps.
- The public address in the network popup, off until you turn it on
  under General, sends one HTTPS GET per address family to `api.ipify.org`
  and `api6.ipify.org`, or only to the URLs you set instead. A request goes
  out when that popup opens, unless any Ringside widget asked in the last
  minute, and when the route changes while it stays open, never sooner than
  a minute after the last; *Try again* after a failed check asks at once;
  never while the popup is closed or there is no connection, and never to
  ipify.org when a URL of your own is set or invalid. It carries the
  User-Agent `ringside/<version>` and `Accept-Language: *`, not your
  languages. The service sees your address, as any website does. Answers
  stay in memory. Qt keeps any cookie the
  service sets until Plasma restarts and sends it back with later requests.
  Qt follows a redirect, to another host or to plain http alike, with the
  same headers; Ringside then ignores any answer that didn't
  come over HTTPS from the host it asked. A reply longer than an address is
  ignored too, but Qt has no way to stop reading it, so a service that
  never stops sending keeps doing so until Plasma restarts.
- The Claude item sends your Claude Code login only to Anthropic
  (`api.anthropic.com`, and `platform.claude.com` to renew an expired
  token). Each check's result, even an error or a sign-out, is kept for
  five minutes and shared by every Ringside widget; when Anthropic asks for
  a longer wait, Ringside waits that long, up to a day.
- The Codex item talks only to `codex app-server`, running locally, which
  contacts OpenAI with the Codex CLI's own login.
- The session starter, off by default, sends the word "Hi" through the
  Claude Code or Codex CLI when a session or week ends, counted against your
  limits like any message. To choose Codex's model it reads the Codex CLI's
  model list in `~/.codex/models_cache.json`.
