# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Tell the workflow whether a PR changes only documentation."""

import json
import os
import re
import subprocess
from pathlib import Path


DOCUMENTS = {
    "README.md", "CONTRIBUTING.md", "CHANGELOG.md",
    "docs/panel.png", "docs/popups.png", "docs/usage.png",
}


def changed_paths(base, head):
    # The PR's own changes since it left its base, as GitHub lists them.
    # --no-renames includes both sides, and NULs keep unusual filenames intact.
    if not all(re.fullmatch(r"[0-9a-f]{40}", sha or "") and set(sha) != {"0"}
               for sha in (base, head)):
        raise ValueError("missing comparison commit")
    result = subprocess.run(
        ["git", "diff", "--no-renames", "--name-only", "-z", base + "..." + head, "--"],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    return result.stdout.decode("utf-8").rstrip("\0").split("\0")


def docs_only(event, diff=changed_paths):
    pr = event["pull_request"]
    try:
        paths = diff(pr["base"]["sha"], pr["head"]["sha"])
    except (ValueError, UnicodeError, subprocess.CalledProcessError):
        print("Comparison unavailable; running the full checks.")
        return False
    return bool(paths) and all(path in DOCUMENTS for path in paths)


def main():
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    docs = "true" if docs_only(event) else "false"
    print(f"Docs only: {docs}")
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write(f"docs={docs}\n")


if __name__ == "__main__":
    main()
