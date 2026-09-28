// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

.pragma library

// Secondary text (captions, units, legends) is the text colour at reduced
// alpha. The mock's 0.6 reads well on dark schemes but falls under WCAG AA
// contrast on light ones, which get 0.72. Pass the Kirigami.Theme.textColor
// of the item being drawn, since the panel and popups use different colour sets.
function dim(textColor) {
    const light = 0.299 * textColor.r + 0.587 * textColor.g + 0.114 * textColor.b > 0.5;
    return Qt.alpha(textColor, light ? 0.6 : 0.72);
}
