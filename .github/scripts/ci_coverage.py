# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

"""Choose full checks unless a complete diff proves a docs-only change."""

import json
import os
import re
import subprocess
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path


DEVELOPMENT_PREFIXES = ("codex/", "fix/", "feat/", "feature/", "docs/", "ci/")
DOCUMENTS = {
    "README.md", "CONTRIBUTING.md", "CHANGELOG.md",
    "docs/panel.png", "docs/popups.png", "docs/standalone.png",
    "docs/usage.png", "docs/fold.gif",
}


def development(event_name, event, ref):
    default = event["repository"]["default_branch"]
    if event_name == "pull_request":
        pr = event["pull_request"]
        branch = pr["head"]["ref"]
        return pr["base"]["ref"] == default and branch != default and branch.startswith(DEVELOPMENT_PREFIXES)
    if event_name == "push" and ref.startswith("refs/heads/"):
        branch = ref.removeprefix("refs/heads/")
        return branch != default and branch.startswith(DEVELOPMENT_PREFIXES)
    return False


def changed_paths(before, after):
    # --no-renames includes both sides, and NULs keep unusual filenames intact.
    if not all(re.fullmatch(r"[0-9a-f]{40}", sha or "") and set(sha) != {"0"}
               for sha in (before, after)):
        raise ValueError("missing comparison commit")
    result = subprocess.run(
        ["git", "diff", "--no-renames", "--name-only", "-z", before, after, "--"],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
    )
    return result.stdout.decode("utf-8").rstrip("\0").split("\0")


def push_base(event, sha):
    # A cancelled earlier push may contain code; compare the entire branch.
    default = "refs/remotes/origin/" + event["repository"]["default_branch"]
    return subprocess.check_output(["git", "merge-base", "--", sha, default],
                                   stderr=subprocess.PIPE).decode().strip()


def api_get(path, token):
    request = urllib.request.Request("https://api.github.com" + path, headers={
        "Authorization": "Bearer " + token,
        "Accept": "application/vnd.github+json",
    })
    with urllib.request.urlopen(request, timeout=5) as response:
        return json.load(response)


def pr_run_exists(pr, repository, token, get):
    query = urllib.parse.urlencode({"event": "pull_request", "head_sha": pr["head"]["sha"], "per_page": 100})
    path = "/repos/" + urllib.parse.quote(repository, safe="/") + "/actions/workflows/test.yml/runs?" + query
    for run in get(path, token)["workflow_runs"]:
        active = run["status"] in ("queued", "in_progress")
        passed = run["status"] == "completed" and run["conclusion"] == "success"
        if (run["event"] != "pull_request" or not (active or passed)
                or run["head_sha"] != pr["head"]["sha"]
                or run["head_repository"]["full_name"].lower() != repository.lower()):
            continue
        for associated in run["pull_requests"]:
            if (associated["number"] == pr["number"]
                    and associated["head"]["sha"] == pr["head"]["sha"]
                    and associated["base"]["sha"] == pr["base"]["sha"]):
                # The workflow records its immutable GITHUB_SHA in the step
                # name; PR associations alone can reflect later base updates.
                jobs_path = "/repos/" + urllib.parse.quote(repository, safe="/") + "/actions/runs/" + str(int(run["id"])) + "/jobs"
                marker = "Choose coverage for " + pr["merge_commit_sha"]
                for job in get(jobs_path, token)["jobs"]:
                    if any(step["name"] == marker and step["conclusion"] == "success"
                           for step in job.get("steps", [])):
                        return True
    return False


def pr_covers_push(event, ref, sha, repository, token, get=api_get):
    # Exact same-repository draft heads defer duplicate pushes too.
    # Ready PRs need successful classification of their current merge commit.
    if not repository or not token:
        return False
    branch = ref.removeprefix("refs/heads/")
    default = event["repository"]["default_branch"]
    owner = repository.split("/")[0]
    query = urllib.parse.urlencode({"state": "open", "head": owner + ":" + branch,
                                    "base": default, "per_page": 100})
    prefix = "/repos/" + urllib.parse.quote(repository, safe="/") + "/pulls"
    def matches(pr):
        return (pr["state"] == "open" and pr["head"]["sha"] == sha
                and pr["head"]["ref"] == branch
                and pr["head"]["repo"]["full_name"].lower() == repository.lower()
                and pr["base"]["ref"] == default)
    try:
        for pr in get(prefix + "?" + query, token):
            if not matches(pr):
                continue
            current = get(prefix + "/" + str(int(pr["number"])), token)
            if matches(current) and current.get("draft") is True:
                print(f"PR #{pr['number']} is a draft at this exact head; deferring branch checks.")
                return True
            if (matches(current) and current.get("mergeable") is True
                    and re.fullmatch(r"[0-9a-f]{40}", current.get("merge_commit_sha") or "")
                    and pr_run_exists(current, repository, token, get)):
                print(f"PR #{pr['number']} covers this exact push; keeping its merge-context checks.")
                return True
    except (urllib.error.URLError, TimeoutError, ValueError, TypeError, KeyError) as error:
        code = f" (HTTP {error.code})" if isinstance(error, urllib.error.HTTPError) else ""
        print(f"PR coverage lookup unavailable{code}; keeping branch checks.")
    return False


def coverage(event_name, event, ref, sha, diff=changed_paths, base=push_base,
             repository="", token="", covered=pr_covers_push):
    if event_name == "pull_request":
        # A ready PR must validate its final merge head, including docs changes.
        if event["pull_request"]["base"]["ref"] == event["repository"]["default_branch"]:
            return "draft" if event["pull_request"].get("draft") is True else "full"
        return "full"
    if not development(event_name, event, ref):
        return "full"
    if event_name == "push" and covered(event, ref, sha, repository, token):
        return "covered"
    try:
        before = event["pull_request"]["base"]["sha"] if event_name == "pull_request" else base(event, sha)
        paths = diff(before, sha)
    except (ValueError, UnicodeError, subprocess.CalledProcessError):
        print("Comparison unavailable; running full checks.")
        return "full"
    return "docs" if paths and all(path in DOCUMENTS for path in paths) else "full"


def main():
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    mode = coverage(os.environ["GITHUB_EVENT_NAME"], event,
                    os.environ["GITHUB_REF"], os.environ["GITHUB_SHA"],
                    repository=os.environ.get("GITHUB_REPOSITORY", ""),
                    token=os.environ.get("GH_TOKEN", ""))
    print(f"Coverage: {mode}")
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write(f"mode={mode}\n")


if __name__ == "__main__":
    main()
