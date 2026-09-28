# Claude is signed out; the codex CLI isn't installed.
from fake_usage import report

report(claude={"status": "signed_out"},
       codex={"status": "error", "message": "codex CLI not found"})
