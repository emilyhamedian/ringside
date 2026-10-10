# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from ci_coverage import changed_paths, docs_only


SHA = "a" * 40


def event(base="b" * 40, head=SHA):
    return {"pull_request": {"base": {"sha": base}, "head": {"sha": head}}}


class DocsOnlyTests(unittest.TestCase):
    def test_allowlist(self):
        docs = ["README.md", "CONTRIBUTING.md", "CHANGELOG.md",
                "docs/panel.png", "docs/popups.png", "docs/usage.png"]
        self.assertTrue(docs_only(event(), lambda *_: docs))
        for path in ("package/metadata.json", "docs/new.png", "README.md\ncode.qml"):
            with self.subTest(path=path):
                self.assertFalse(docs_only(event(), lambda *_, path=path: ["README.md", path]))

    def test_compares_the_prs_base_and_head(self):
        seen = []
        docs_only(event(base="c" * 40, head="d" * 40), lambda *shas: seen.append(shas) or ["README.md"])
        self.assertEqual(seen, [("c" * 40, "d" * 40)])

    def test_empty_or_missing_comparison_runs_the_checks(self):
        self.assertFalse(docs_only(event(), lambda *_: []))
        def unavailable(*_):
            raise ValueError("missing commit")
        self.assertFalse(docs_only(event(), unavailable))
        for sha in ("0" * 40, "", "--help", None):
            with self.subTest(sha=sha), self.assertRaises(ValueError):
                changed_paths(sha, SHA)

    def test_real_diff(self):
        with tempfile.TemporaryDirectory() as folder:
            def git(*args):
                return subprocess.check_output(["git", "-c", "commit.gpgsign=false", "-C", folder, *args],
                                               stderr=subprocess.DEVNULL).decode().strip()
            def commit(message):
                git("add", "-A")
                git("commit", "-q", "-m", message)
                return git("rev-parse", "HEAD")
            git("init", "-q")
            git("config", "user.name", "CI test")
            git("config", "user.email", "ci@example.invalid")
            Path(folder, "code.qml").write_text("test")
            start = commit("start")
            # Code that lands on the base after the branch left it isn't
            # the PR's change.
            Path(folder, "code.qml").write_text("changed on main")
            base = commit("main moves on")
            git("checkout", "-q", "-b", "fix/readme", start)
            Path(folder, "README.md").write_text("docs")
            readme = commit("docs")
            # A rename from code to an allowed document must run the checks.
            Path(folder, "README.md").unlink()
            Path(folder, "code.qml").rename(Path(folder, "README.md"))
            Path(folder, "docs\ncode.qml").write_text("test")
            renamed = commit("rename")
            original = os.getcwd()
            try:
                os.chdir(folder)
                self.assertEqual(changed_paths(base, readme), ["README.md"])
                self.assertTrue(docs_only(event(base, readme)))
                paths = changed_paths(base, renamed)
                self.assertFalse(docs_only(event(base, renamed)))
            finally:
                os.chdir(original)
            self.assertEqual(set(paths), {"code.qml", "README.md", "docs\ncode.qml"})


if __name__ == "__main__":
    unittest.main()
