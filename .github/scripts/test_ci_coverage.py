# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

import copy
import subprocess
import tempfile
import unittest
import urllib.error
import urllib.parse
from pathlib import Path

from ci_coverage import coverage, changed_paths, development, pr_covers_push


SHA = "a" * 40
EVENT = {"repository": {"default_branch": "main"}, "before": "b" * 40}


class CoverageTests(unittest.TestCase):
    def mode(self, paths, event=EVENT, ref="refs/heads/fix/checks", name="push"):
        return coverage(name, event, ref, SHA, lambda *_: paths, lambda *_: "b" * 40)

    def test_allowlist(self):
        self.assertEqual(self.mode(["README.md", "docs/panel.png"]), "docs")
        for path in ("AGENTS.md", "CLAUDE.md", "SECURITY.md", ".agents/skills/check/SKILL.md",
                     ".github/workflows/test.yml", "REUSE.toml", "LICENSE",
                     "docs/new.png", "docs/tool.py", "package/metadata.json", "README.md\ncode.qml"):
            with self.subTest(path=path):
                self.assertEqual(self.mode(["README.md", path]), "full")

    def test_unclassified_branches_and_tags(self):
        for ref in ("refs/heads/main", "refs/heads/release", "refs/heads/release/1",
                    "refs/heads/v0.2", "refs/heads/unknown", "refs/tags/fix/tag", "refs/tags/v0.2.0"):
            with self.subTest(ref=ref):
                self.assertEqual(self.mode(["README.md"], ref=ref), "full")
                self.assertFalse(development("push", EVENT, ref))

    def test_draft_and_fork_pr_use_merge_diff(self):
        for draft in (False, True):
            event = {**EVENT, "pull_request": {"draft": draft,
                "head": {"ref": "fix/checks", "sha": "c" * 40, "repo": {"full_name": "fork/repo"}},
                "base": {"ref": "main", "sha": "b" * 40}}}
            def diff(before, after):
                self.assertEqual((before, after), ("b" * 40, SHA))
                return ["README.md"]
            self.assertEqual(coverage("pull_request", event, "refs/pull/2/merge", SHA, diff), "docs")
            event["pull_request"]["base"]["ref"] = "release/1"
            self.assertEqual(self.mode(["README.md"], event, "refs/pull/2/merge", "pull_request"), "full")

    def test_empty_or_missing_comparison_is_full(self):
        self.assertEqual(self.mode([]), "full")
        def unavailable(*_):
            raise ValueError("missing commit")
        self.assertEqual(coverage("push", EVENT, "refs/heads/fix/checks", SHA,
                                  unavailable, lambda *_: "b" * 40), "full")
        self.assertEqual(coverage("push", EVENT, "refs/heads/fix/checks", SHA,
                                  lambda *_: ["README.md"], unavailable), "full")
        for before in ("0" * 40, "", "--help"):
            with self.assertRaises(ValueError):
                changed_paths(before, SHA)

    def test_real_diff_keeps_renames_and_unusual_names(self):
        # A rename from code to an allowed document must still run full checks.
        with tempfile.TemporaryDirectory() as folder:
            def git(*args):
                return subprocess.check_output(["git", "-c", "commit.gpgsign=false", "-C", folder, *args],
                                               stderr=subprocess.DEVNULL).decode().strip()
            git("init")
            git("config", "user.name", "CI test")
            git("config", "user.email", "ci@example.invalid")
            Path(folder, "code.qml").write_text("test")
            git("add", ".")
            git("commit", "-m", "before")
            before = git("rev-parse", "HEAD")
            git("update-ref", "refs/remotes/origin/main", before)
            # A code push cancelled by a docs push must still get full coverage.
            Path(folder, "code.qml").write_text("changed code")
            git("add", ".")
            git("commit", "-m", "code push")
            code_push = git("rev-parse", "HEAD")
            Path(folder, "README.md").write_text("docs")
            git("add", ".")
            git("commit", "-m", "docs push")
            docs_push = git("rev-parse", "HEAD")
            Path(folder, "README.md").unlink()
            Path(folder, "code.qml").rename(Path(folder, "README.md"))
            Path(folder, "docs\ncode.qml").write_text("test")
            git("add", ".")
            git("commit", "-m", "after")
            after = git("rev-parse", "HEAD")
            import os
            original = os.getcwd()
            try:
                os.chdir(folder)
                self.assertEqual(changed_paths(code_push, docs_push), ["README.md"])
                self.assertEqual(coverage("push", {**EVENT, "before": code_push},
                                          "refs/heads/fix/checks", docs_push), "full")
                paths = changed_paths(before, after)
            finally:
                os.chdir(original)
            self.assertEqual(set(paths), {"code.qml", "README.md", "docs\ncode.qml"})
            self.assertEqual(self.mode(paths), "full")


class PullRequestCoverageTests(unittest.TestCase):
    def setUp(self):
        self.pr = {"number": 2, "state": "open", "draft": True,
                   "head": {"sha": SHA, "ref": "fix/checks", "repo": {"full_name": "owner/ringside"}},
                   "base": {"ref": "main", "sha": "b" * 40}, "mergeable": True, "merge_commit_sha": "c" * 40}
        self.run = {"id": 10, "event": "pull_request", "status": "in_progress", "conclusion": None,
                    "head_sha": SHA, "head_repository": {"full_name": "owner/ringside"},
                    "pull_requests": [{"number": 2, "head": {"sha": SHA}, "base": {"sha": "b" * 40}}]}

    def covered(self, current=None, listing=None, runs=None, steps=None):
        def get(path, token):
            self.assertEqual(token, "test-token")
            self.assertTrue(path.startswith("/repos/owner/ringside/"))
            if path.endswith("/jobs"):
                return {"jobs": [{"steps": [{"name": "Choose coverage for " + "c" * 40,
                                            "conclusion": "success"}] if steps is None else steps}]}
            if "/actions/" in path:
                return {"workflow_runs": [self.run] if runs is None else runs}
            if "?" in path:
                query = urllib.parse.parse_qs(urllib.parse.urlsplit(path).query)
                self.assertEqual(query["head"], ["owner:fix/checks"])
                return [self.pr] if listing is None else listing
            self.assertTrue(path.endswith("/2"))
            return self.pr if current is None else current
        return pr_covers_push(EVENT, "refs/heads/fix/checks", SHA, "owner/ringside", "test-token", get)

    def test_exact_same_repo_mergeable_draft_is_covered(self):
        self.assertTrue(self.covered())
        self.assertFalse(self.covered(listing=[]))

    def test_mergeability_without_matching_run_keeps_branch_checks(self):
        self.assertFalse(self.covered(runs=[]))
        self.assertFalse(self.covered(steps=[]))
        self.assertFalse(self.covered(steps=[{"name": "Choose coverage for " + "d" * 40, "conclusion": "success"}]))
        self.assertFalse(self.covered(steps=[{"name": "Choose coverage for " + "c" * 40, "conclusion": None}]))
        mutations = (
            lambda run: run.update(event="push"),
            lambda run: run.update(status="waiting"),
            lambda run: run.update(status="completed", conclusion="cancelled"),
            lambda run: run.update(status="completed", conclusion="failure"),
            lambda run: run.update(head_sha="d" * 40),
            lambda run: run["head_repository"].update(full_name="fork/ringside"),
            lambda run: run.update(pull_requests=[]),
            lambda run: run["pull_requests"][0].update(number=3),
            lambda run: run["pull_requests"][0]["base"].update(sha="d" * 40),
        )
        for mutate in mutations:
            run = copy.deepcopy(self.run)
            mutate(run)
            self.assertFalse(self.covered(runs=[run]))
        passed = {**self.run, "status": "completed", "conclusion": "success"}
        self.assertTrue(self.covered(runs=[passed]))

    def test_stale_fork_conflicted_closed_unknown_or_release_pr_keeps_checks(self):
        mutations = (
            lambda pr: pr.update(state="closed"),
            lambda pr: pr["head"].update(sha="d" * 40),
            lambda pr: pr["head"].update(ref="fix/other"),
            lambda pr: pr["head"]["repo"].update(full_name="fork/ringside"),
            lambda pr: pr["base"].update(ref="release/1"),
            lambda pr: pr.update(mergeable=False),
            lambda pr: pr.update(mergeable=None),
            lambda pr: pr.update(merge_commit_sha=None),
        )
        for mutate in mutations:
            current = copy.deepcopy(self.pr)
            mutate(current)
            with self.subTest(current=current):
                self.assertFalse(self.covered(current=current))

    def test_lookup_failure_or_missing_token_keeps_checks(self):
        for error in (urllib.error.URLError("denied"), TimeoutError(), ValueError(), TypeError(), KeyError()):
            def unavailable(*_, error=error):
                raise error
            self.assertFalse(pr_covers_push(EVENT, "refs/heads/fix/checks", SHA,
                                           "owner/ringside", "test-token", unavailable))
        self.assertFalse(pr_covers_push(EVENT, "refs/heads/fix/checks", SHA, "owner/ringside", ""))

    def test_protected_refs_and_pr_events_never_deduplicate(self):
        def forbidden(*_):
            self.fail("unexpected PR lookup")
        for ref in ("refs/heads/main", "refs/heads/release/1", "refs/heads/v0.2", "refs/tags/fix/tag"):
            self.assertEqual(coverage("push", EVENT, ref, SHA, covered=forbidden), "full")
        event = {**EVENT, "pull_request": self.pr}
        event["pull_request"]["base"]["sha"] = "b" * 40
        self.assertEqual(coverage("pull_request", event, "refs/pull/2/merge", SHA,
                                  diff=lambda *_: ["package/main.qml"], covered=forbidden), "full")
        self.assertEqual(coverage("push", EVENT, "refs/heads/fix/checks", SHA,
                                  covered=lambda *_: True), "covered")


if __name__ == "__main__":
    unittest.main()
