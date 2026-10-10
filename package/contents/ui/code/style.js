// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

.pragma library

// Secondary text (captions, units, legends) is the text colour at reduced
// alpha: 0.6 reads well on dark schemes but falls under WCAG AA contrast on
// light ones, which get 0.72. Pass the Kirigami.Theme.textColor of the item
// being drawn, since the panel and popups use different colour sets.
function dim(textColor) {
    const light = 0.299 * textColor.r + 0.587 * textColor.g + 0.114 * textColor.b > 0.5;
    return Qt.alpha(textColor, light ? 0.6 : 0.72);
}

// A unit after its number in a popup reading: two thirds the size of the
// digits, as in the countdown's "5d 18h", but never under the small font, so
// a unit after body-sized digits stays legible.
function unitPointSize(pointSize, smallPointSize) {
    return Math.max(pointSize * 0.67, smallPointSize);
}

// The gap between a number and its unit, in pixels for digits of the given
// point size: about a space of the unit's own size, so the slash in
// "1.6 / 8 GiB" sits centred.
function unitGap(pointSize) {
    return Math.round(pointSize * 0.4);
}

// Where a popup's readings, headers and rules start and end, in from its
// sides, in pixels.
function contentEdge(largeSpacing) {
    return Math.round(largeSpacing * 2);
}

// A reading's colour at a level: red at 2, amber at 1, else `base`, the
// text colour unless given. Pass the Kirigami.Theme of the item being drawn.
function levelColor(level, theme, base) {
    return level === 2 ? theme.negativeTextColor : level === 1 ? theme.neutralTextColor : base ?? theme.textColor;
}

// The size of a tile's reading, "4.61 GHz" or "0.42", for the default
// font's point size.
function tilePointSize(pointSize) {
    return pointSize * 1.38;
}

// The popups' graphs: their height in grid units, and as alphas of the
// line's colour the area under a line and the fainter band up to each
// bucket's highest reading. TRACK is the text colour's alpha for the track
// a bar runs along and for the rules between sections.
const GRAPH_HEIGHT = 2.7;
const AREA = 0.15;
const BAND = 0.6 * AREA;
const TRACK = 0.08;

// The height of a font's capitals, or of whatever `sample` measures in it
// in their place: FontMetrics.capitalHeight needs Qt 6.9, and before that
// the ink of a sample such as "H" stands in.
function capHeight(metrics, sample) {
    return metrics.capitalHeight ?? sample.tightBoundingRect.height;
}

// Whether to animate: at Plasma's Instant speed Kirigami's durations are a
// millisecond or so rather than none. Pass Kirigami.Units.
function animated(units) {
    return units.longDuration > 1;
}

// An arrow beside a rate, as wide as this times its height.
const ARROW_ASPECT = 0.8;
