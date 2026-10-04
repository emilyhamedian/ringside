// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.kde.kirigami as Kirigami
import "code/format.js" as Format

// The face the panel's readings are set in, in both layouts: the theme's sans,
// heavier for a ring's own reading, with figures of one width so a number
// keeps its place as it changes. Text draws at half points while metrics
// measure at any size, so the size is rounded here, and the same fonts both
// measure and draw.
QtObject {
    id: face

    // The inline strip's size, which its rates share; the Standalone dials
    // and a vertical panel's rates set their own.
    readonly property real panelPointSize: Kirigami.Theme.defaultFont.pointSize * 0.9
    property real pointSize: panelPointSize
    readonly property real drawnSize: Math.max(1, Math.round(pointSize * 2) / 2)

    readonly property FontMetrics strong: FontMetrics {
        font.family: Kirigami.Theme.defaultFont.family
        font.pointSize: face.drawnSize
        font.weight: Font.DemiBold
        font.features: ({ "tnum": 1 })
    }
    readonly property FontMetrics plain: FontMetrics {
        font.family: Kirigami.Theme.defaultFont.family
        font.pointSize: face.drawnSize
        font.features: ({ "tnum": 1 })
    }
    readonly property TextMetrics capSample: TextMetrics {
        font: face.strong.font
        text: "H"
    }

    // One line of either weight, in whole pixels, so lines stacked in
    // different places land on the same rows.
    readonly property real lineHeight: Math.ceil(Math.max(strong.height, plain.height))
    // capitalHeight needs Qt 6.9; the ink of "H" stands in before that and can
    // round a pixel taller.
    readonly property real capHeight: strong.capitalHeight ?? capSample.tightBoundingRect.height // qmllint disable missing-property

    readonly property var digits: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9].map(d => Format.whole(d))
    readonly property var digitPattern: new RegExp("[0-9" + digits.join("") + "]", "g")

    // The whole pixels the widest of `texts` needs in `metrics`, with every
    // digit, the locale's or ASCII, counted as the widest one. That holds
    // where a font has no figures of one width, or a fallback font draws the
    // locale's digits. Reading the height ties a binding that calls this to
    // the font once it has loaded, as advanceWidth() alone would not.
    function room(metrics, texts) {
        if (!(metrics.height > 0)) {
            return 0;
        }
        const widest = digits.reduce((a, b) => metrics.advanceWidth(b) > metrics.advanceWidth(a) ? b : a);
        return Math.ceil(Math.max(0, ...texts.map(text => metrics.advanceWidth(String(text).replace(digitPattern, widest)))));
    }
}
