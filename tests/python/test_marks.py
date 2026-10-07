# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

import re
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ICONS = ROOT / "package" / "contents" / "icons"
MARKS = ROOT / "package" / "contents" / "ui" / "code" / "marks.js"
SVG = "{http://www.w3.org/2000/svg}"


def marks():
    """Each mark in marks.js as a dict of its fields, by its variable's name."""
    source = MARKS.read_text(encoding="utf-8")
    found = {}
    for name, body in re.findall(r"var (\w+) = \{(.*?)\n\};", source, re.S):
        fields = dict(re.findall(r'(\w+): ("[^"]*"|\[[^\]]*\]|[-0-9.]+)', body))
        found[name] = {
            key: [float(n) for n in value[1:-1].split(",")] if value.startswith("[")
            else value[1:-1] if value.startswith('"') else float(value)
            for key, value in fields.items()
        }
    return found


def icon(name):
    """An icon's viewBox, and its one path's fill rule and data."""
    root = ET.parse(ICONS / name).getroot()
    paths = root.findall(f".//{SVG}path")
    assert len(paths) == 1, f"{name} has {len(paths)} paths"
    view_box = [float(n) for n in root.get("viewBox").split()]
    return view_box, paths[0].get("fill-rule", "nonzero"), paths[0].get("d")


class MarksTest(unittest.TestCase):
    """The panel draws the marks from marks.js; the SVGs stay their source."""

    def test_marks_are_the_icons(self):
        found = marks()
        self.assertEqual(sorted(found), ["CLAUDE", "CODEX"])
        for name, svg in (("CLAUDE", "claude.svg"), ("CODEX", "codex.svg")):
            with self.subTest(mark=name):
                mark = found[name]
                view_box, fill_rule, d = icon(svg)
                self.assertEqual(mark["path"], d)
                # RingName fills every mark by the nonzero rule, so a mark's
                # holes must be wound against its outline.
                self.assertEqual(fill_rule, "nonzero")
                # RingName scales a square box; [x, y, size] is the viewBox
                # with its equal width and height given once.
                self.assertEqual(view_box[2], view_box[3], f"{svg} is square")
                self.assertEqual(mark["box"], view_box[:3])


if __name__ == "__main__":
    unittest.main()
