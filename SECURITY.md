# Security

Report a vulnerability privately through GitHub's
[private vulnerability reporting](https://github.com/emilyhamedian/ringside/security/advisories/new),
rather than a public issue.

## Scope

Mainly the two helpers Ringside runs:

- `package/contents/code/usage.py` reads your Claude Code and Codex CLI
  credentials to poll usage limits, and can refresh the Claude Code token,
  writing it back the way Claude Code itself does.
- `package/contents/code/ringside-info.sh` reads `/proc`, `/sys` and udev's
  database as your user.

## What Ringside reads and sends

- System items (CPU, GPU, memory, network, disk) read `/proc`, `/sys`,
  udev's database and ksystemstats, and send nothing.
- The Claude item sends your Claude Code login only to Anthropic
  (`api.anthropic.com`, and `platform.claude.com` to renew an expired
  token).
- The Codex item talks only to `codex app-server`, running locally.
