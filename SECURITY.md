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
- `package/contents/code/ringside-info.sh` reads `/proc`, `/sys` and udev's
  database as your user.

## What Ringside reads and sends

- System items (CPU, GPU, memory, network, disk) read `/proc`, `/sys`,
  udev's database and ksystemstats, and send nothing.
- The Claude item sends your Claude Code login only to Anthropic
  (`api.anthropic.com`, and `platform.claude.com` to renew an expired
  token). Each check's result, even an error or a sign-out, is kept for
  five minutes and shared by every Ringside widget; when Anthropic asks for
  a longer wait, Ringside waits that long, up to a day.
- The Codex item talks only to `codex app-server`, running locally, which
  contacts OpenAI with the Codex CLI's own login.
