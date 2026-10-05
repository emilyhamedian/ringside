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
    """Each mark in marks.js as (box, path), by its variable's name."""
    source = MARKS.read_text(encoding="utf-8")
    found = {}
    for name, box, path in re.findall(
        r'var (\w+) = \{\s*box: \[([^\]]*)\],\s*path: "([^"]*)"\s*\};', source
    ):
        found[name] = ([float(n) for n in box.split(",")], path)
    return found


def icon(name):
    """The viewBox and the one path's data of an icon in icons/."""
    root = ET.parse(ICONS / name).getroot()
    paths = root.findall(f".//{SVG}path")
    assert len(paths) == 1, f"{name} has {len(paths)} paths"
    return [float(n) for n in root.get("viewBox").split()], paths[0].get("d")


class MarksTest(unittest.TestCase):
    """The panel draws the marks from marks.js; the SVGs stay their source."""

    def test_marks_are_the_icons(self):
        found = marks()
        self.assertEqual(sorted(found), ["CLAUDE", "OPENAI"])
        for name, svg in (("CLAUDE", "claude.svg"), ("OPENAI", "openai.svg")):
            with self.subTest(mark=name):
                box, path = found[name]
                view_box, d = icon(svg)
                self.assertEqual(path, d)
                # RingName scales a square box; [x, y, size] is the viewBox
                # with its equal width and height given once.
                self.assertEqual(view_box[2], view_box[3], f"{svg} is square")
                self.assertEqual(box, view_box[:3])


if __name__ == "__main__":
    unittest.main()
