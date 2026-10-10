#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
# SPDX-License-Identifier: GPL-3.0-or-later

# Draws the logo: the panel's gauge ring over "Ringside" in Nunito, outlined
# so the files need no font. Writes docs/logo.svg for the README, docs/social-preview.png for GitHub's social preview, and
# package/contents/icons/ringside.svg for the widget's icon.
#
# Needs fontTools, Nunito (ttf-nunito on Arch, fonts-nunito elsewhere, or set
# NUNITO to its folder) and rsvg-convert.
#
# Usage: python3 scripts/logo.py

import os
import re
import subprocess
import sys

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
BLUE, AMBER, DARK, LIGHT = "#3daee9", "#f67400", "#232629", "#fcfcfc"
# The README's wordmark: a grey that reads on GitHub's light and dark pages
# alike, since not every viewer says which it shows.
MUTED = "#7d8590"
HEADER = """<!--
SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
SPDX-License-Identifier: GPL-3.0-or-later
-->
"""


def font_path(weight):
    for folder in [os.environ.get("NUNITO"), "/usr/share/fonts/ttf-nunito",
                   "/usr/share/fonts/truetype/nunito", "/usr/share/fonts/nunito"]:
        if folder and os.path.exists(os.path.join(folder, f"Nunito-{weight}.ttf")):
            return os.path.join(folder, f"Nunito-{weight}.ttf")
    sys.exit(f"logo.py: Nunito-{weight}.ttf not found; install Nunito or set NUNITO")


def kerning(font, left, right):
    for lookup in font["GPOS"].table.LookupList.Lookup:
        for sub in lookup.SubTable:
            if sub.LookupType == 9:
                sub = sub.ExtSubTable
            if sub.LookupType != 2 or left not in sub.Coverage.glyphs:
                continue
            if sub.Format == 1:
                for pair in sub.PairSet[sub.Coverage.glyphs.index(left)].PairValueRecord:
                    if pair.SecondGlyph == right and pair.Value1:
                        return pair.Value1.XAdvance or 0
            else:
                c1 = sub.ClassDef1.classDefs.get(left, 0)
                c2 = sub.ClassDef2.classDefs.get(right, 0)
                value = sub.Class1Record[c1].Class2Record[c2].Value1
                if value and value.XAdvance:
                    return value.XAdvance
    return 0


def outline(text, weight, size, tracking=0):
    """The text as one SVG path on a baseline at y=0, letters pulled in by
    tracking (a fraction of the em), and its ink width from its left edge."""
    font = TTFont(font_path(weight))
    glyphs, cmap = font.getGlyphSet(), font.getBestCmap()
    names = [cmap[ord(c)] for c in text]
    scale = size / font["head"].unitsPerEm
    pen, bounds, x = SVGPathPen(glyphs), BoundsPen(glyphs), 0
    for i, name in enumerate(names):
        glyphs[name].draw(TransformPen(pen, (scale, 0, 0, -scale, x * scale, 0)))
        glyphs[name].draw(TransformPen(bounds, (scale, 0, 0, -scale, x * scale, 0)))
        x += glyphs[name].width + tracking * font["head"].unitsPerEm
        if i + 1 < len(names):
            x += kerning(font, name, names[i + 1])
    left, _, right, _ = bounds.bounds
    path = re.sub(r"(\d+\.\d{2})\d+", r"\1", pen.getCommands())
    return path, right - left, left


def ring(cx, cy, size, track):
    """The gauge at 72%, blue outside and a second GPU's amber inside, in a box of size."""
    s = size / 100

    def at(x, y):
        return f"{cx + (x - 50) * s:.2f},{cy + (y - 50) * s:.2f}"

    return (f'<circle cx="{cx:.2f}" cy="{cy:.2f}" r="{40 * s:.2f}" fill="none" stroke="{track}" stroke-width="{11 * s:.2f}"/>'
            f'<path d="M{at(50, 10)} A{40 * s:.2f},{40 * s:.2f} 0 1 1 {at(10.7, 57.5)}" fill="none" stroke="{BLUE}" stroke-width="{11 * s:.2f}" stroke-linecap="round"/>'
            f'<circle cx="{cx:.2f}" cy="{cy:.2f}" r="{26 * s:.2f}" fill="none" stroke="{track}" stroke-width="{7 * s:.2f}"/>'
            f'<path d="M{at(50, 24)} A{26 * s:.2f},{26 * s:.2f} 0 0 1 {at(72.5, 63)}" fill="none" stroke="{AMBER}" stroke-width="{7 * s:.2f}" stroke-linecap="round"/>')


def track(text, alpha=0.22):
    r, g, b = (int(text[i:i + 2], 16) for i in (1, 3, 5))
    return f"rgba({r},{g},{b},{alpha})"


def write(path, body):
    with open(os.path.join(ROOT, path), "w") as f:
        f.write(HEADER + body)


# Nunito SemiBold at 100, pulled in 3% of the em: caps 70.5 tall, descender 20
# deep. The width and left edge are the ink's, so the word centres on its ink.
word, word_width, word_left = outline("Ringside", "SemiBold", 100, -0.03)


def stacked(text, alpha):
    """The mark over the wordmark, for the README."""
    width, mark, word_w = 400, 120, 240
    s = word_w / word_width
    height = 10 + mark + 12 + 95 * s + 10
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height:.0f}" viewBox="0 0 {width} {height:.0f}" role="img" aria-label="Ringside">\n'
            + ring(width / 2, 10 + mark / 2, mark, track(text, alpha))
            + f'\n<path fill="{text}" transform="translate({(width - word_w) / 2 - word_left * s:.2f},{10 + mark + 12 + 75 * s:.2f}) scale({s:.4f})" d="{word}"/>\n</svg>\n')


write("docs/logo.svg", stacked(MUTED, 0.30))
# The icon's track is a fixed grey, since it sits on light and dark panels alike.
write("package/contents/icons/ringside.svg",
      '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">\n'
      + ring(50, 50, 100, "#9a9ea2") + "\n</svg>\n")

# The social preview: the mark beside the wordmark on Breeze Dark, with the
# one-line pitch under them.
line, line_width, line_left = outline("System monitor rings for your KDE Plasma 6 panel", "SemiBold", 100)
mark, word_w, gap, cy = 190, 560, 44, 280
s, ls = word_w / word_width, 0.34
left = (1280 - mark - gap - word_w) / 2
preview = (f'<svg xmlns="http://www.w3.org/2000/svg" width="1280" height="640" viewBox="0 0 1280 640">\n'
           f'<rect width="1280" height="640" fill="{DARK}"/>\n'
           + ring(left + mark / 2, cy, mark, track(LIGHT))
           + f'\n<path fill="{LIGHT}" transform="translate({left + mark + gap - word_left * s:.2f},{cy + 35.25 * s:.2f}) scale({s:.4f})" d="{word}"/>\n'
           f'<path fill="{LIGHT}" fill-opacity="0.72" transform="translate({(1280 - line_width * ls) / 2 - line_left * ls:.2f},{cy + mark / 2 + 76:.2f}) scale({ls:.4f})" d="{line}"/>\n</svg>\n')
subprocess.run(["rsvg-convert", "-o", os.path.join(ROOT, "docs/social-preview.png")], input=preview.encode(), check=True)
