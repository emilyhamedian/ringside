// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

import QtQuick
import org.kde.kirigami as Kirigami
import "code/format.js" as Format
import "code/style.js" as Style

// A number in the theme's face with its unit after it, smaller and dimmer
// and on the same baseline: "4.61 GHz", the countdown's "5d". A temperature's
// "°C" hangs from the top of the digits instead.
// Tabular figures keep the number's width as its digits change, without the
// monospace face's full-width decimal point.
Item {
    id: reading

    // A number and its unit read left to right in every language; mirroring
    // would put "°61" or the unit before the value.
    LayoutMirroring.enabled: false
    LayoutMirroring.childrenInherit: true

    property string value: ""
    property string unit: ""
    // "C" or "F" for a temperature, set as "°C" at the small font's size
    // with the letter's top level with the digits' top. A missing reading's
    // dash gets no unit.
    property string degreeUnit: ""
    property real pointSize: Kirigami.Theme.defaultFont.pointSize
    property color color: Kirigami.Theme.textColor
    property color unitColor: Style.dim(color)
    property real unitSpacing: degreeUnit !== "" ? degreeGap - degreeBearing - trailingRoom(zero) : Style.unitGap(pointSize)
    // The window's scale: with Wayland's fractional scaling the screen
    // reports 2 at 125 %. Qt 6.6 knows only the screen's.
    readonly property real ratio: Window.window?.devicePixelRatio ?? Screen.devicePixelRatio // qmllint disable missing-property
    // The degree sign's ink stands this far from the last digit's ink in
    // the rows the sign covers.
    readonly property real degreeGap: Kirigami.Theme.smallFont.pointSize * 0.45
    // Tabular digits are centred in cells of one width, and up beside the
    // sign a digit whose top falls away, such as a "0" or a "4", leaves more
    // room than a "1" or a "7". Only the sign moves to keep its gap: the
    // width stays the one after a "0", so the digits of a right-aligned
    // reading hold still as they change.
    readonly property real degreeShift: degreeUnit !== "" ? trailingRoom(zero) - roomBesideSign() : 0
    // The heights of a "1" in the locale's digits and of an "H" in the
    // unit's face, whose flat tops the unit lines up. Measured rather than
    // taken from the font's cap height: Arabic-Indic digits are shorter than
    // capitals, and hinting rounds each height to whole pixels.
    readonly property real figureHeight: -figureSample.tightBoundingRect.y
    readonly property real capHeight: -capSample.tightBoundingRect.y
    // How far the unit's baseline sits above the digits'.
    readonly property real degreeLift: degreeUnit !== "" ? figureHeight - capHeight : 0
    // The locale's ten digits, and how the scan drew them and the degree
    // sign, once it is in.
    readonly property string digits: degreeUnit !== "" ? Array.from({ length: 10 }, (_, i) => Format.whole(i)).join("") : ""
    readonly property var scan: glyphScan.item?.scan ?? null // qmllint disable missing-property
    // The scan's pixels per pixel of the number, and the unit's size
    // against the number's.
    readonly property real scanScale: scan ? scan.pixels * scan.digitsWidth / digitsSample.advanceWidth : 1
    readonly property real unitScale: suffix.font.pointSize / number.font.pointSize
    // Where the degree sign's ink starts after its origin. Font metrics
    // round a glyph's box to whole pixels, too coarse for a gap this small.
    readonly property real degreeBearing: scan ? scan.degree.left / scanScale * unitScale : 0
    // Set when a parent speaks for several readings at once.
    property bool accessibleIgnored: false
    readonly property real numberWidth: number.implicitWidth
    readonly property real suffixWidth: suffix.visible ? suffix.implicitWidth : 0
    baselineOffset: number.baselineOffset

    implicitWidth: numberWidth + (suffixWidth > 0 ? unitSpacing + suffixWidth : 0)
    implicitHeight: number.implicitHeight

    function trailingRoom(metrics) {
        return metrics.text === "" ? 0 : metrics.advanceWidth - metrics.tightBoundingRect.x - metrics.tightBoundingRect.width;
    }

    // The room the last digit leaves after its ink in the rows the degree
    // sign covers. Until the scan is in, and for a digit with no ink up
    // there, such as the dot of an Arabic-Indic zero, its ink box stands
    // for it.
    function roomBesideSign() {
        const glyph = scan?.glyphs[lastDigit.text];
        if (glyph === undefined) {
            return trailingRoom(lastDigit);
        }
        const row = y => scan.baseline + y * unitScale - degreeLift * scanScale;
        const last = Math.min(glyph.rows.length, Math.ceil(row(scan.degree.bottom)));
        let reach = -1;
        for (let y = Math.max(0, Math.floor(row(scan.degree.top))); y < last; ++y) {
            reach = Math.max(reach, glyph.rows[y]);
        }
        // The scan draws the digit without tabular figures, which may set
        // it elsewhere in a wider cell.
        const tabular = trailingRoom(lastDigit) - trailingRoom(plainLastDigit);
        return reach < 0 ? trailingRoom(lastDigit) : (glyph.end - reach - 1) / scanScale + tabular;
    }

    TextMetrics {
        id: lastDigit
        font: number.font
        text: reading.degreeUnit !== "" ? reading.value.slice(-1) : ""
    }

    TextMetrics {
        id: zero
        font: number.font
        text: reading.degreeUnit !== "" ? "0" : ""
    }

    TextMetrics {
        id: figureSample
        font: number.font
        text: reading.degreeUnit !== "" ? Format.whole(1) : ""
    }

    TextMetrics {
        id: capSample
        font: suffix.font
        text: reading.degreeUnit !== "" ? "H" : ""
    }

    // The last digit and the ten digits as the scan draws them, in the
    // number's face without tabular figures.
    TextMetrics {
        id: plainLastDigit
        font.family: number.font.family
        font.pointSize: number.font.pointSize
        text: lastDigit.text
    }

    TextMetrics {
        id: digitsSample
        font.family: number.font.family
        font.pointSize: number.font.pointSize
        text: reading.digits
    }

    // Draws the locale's digits and the degree sign large, out of sight,
    // and keeps each digit's rightmost ink in every row, since the gap the
    // eye reads is the one beside the sign, not beside the digit's box.
    // A glyph's shape doesn't depend on tabular figures, which a Canvas
    // can't ask for. Should the scan find no ink, the boxes stand in.
    Loader {
        id: glyphScan
        active: reading.degreeUnit !== ""
        sourceComponent: Canvas {
            readonly property string face: "64px \"" + number.font.family + "\", sans-serif"
            // In the scan's image pixels: how many to a Canvas pixel, the
            // ten digits' width in Canvas pixels, the baseline's row, each
            // digit's advance and rightmost ink per row (-1 for none), and
            // where the degree sign's ink starts, from its origin and from
            // the baseline.
            property var scan: null

            visible: false
            width: 56
            height: 84
            onFaceChanged: requestPaint()
            onAvailableChanged: requestPaint()
            Component.onCompleted: requestPaint()
            onPaint: {
                const context = getContext("2d");
                context.font = face;
                // "start", the default, is the right edge under a
                // right-to-left language.
                context.textAlign = "left";
                // The image is drawn at the screen's scale, which is undone
                // to keep the scan's cost the same at any scale, while
                // getImageData reads its pixels from the corner. A bar of
                // known width tells the scale that results.
                context.setTransform(1 / reading.ratio, 0, 0, 1 / reading.ratio, 0, 0);
                // The leftmost and rightmost inked column of each row, -1
                // for none.
                const draw = paint => {
                    context.clearRect(0, 0, width, height);
                    paint();
                    const image = context.getImageData(0, 0, width, height);
                    const inked = (x, y) => image.data[(y * image.width + x) * 4 + 3] >= 128;
                    const rows = [];
                    for (let y = 0; y < image.height; ++y) {
                        let left = 0;
                        while (left < image.width && !inked(left, y)) {
                            ++left;
                        }
                        let right = image.width - 1;
                        while (right > left && !inked(right, y)) {
                            --right;
                        }
                        rows.push(left < image.width ? [left, right] : [-1, -1]);
                    }
                    return rows;
                };
                const pixels = Math.max(...draw(() => context.fillRect(4, 4, 48, 8)).map(([left, right]) => left < 0 ? 0 : right - left + 1)) / 48;
                const sign = draw(() => context.fillText("°", 4, 72));
                const signRows = sign.map(([left], y) => left < 0 ? -1 : y).filter(y => y >= 0);
                if (pixels === 0 || signRows.length === 0) {
                    scan = null;
                    return;
                }
                const baseline = 72 * pixels;
                const glyphs = {};
                for (const digit of Array.from(reading.digits)) {
                    glyphs[digit] = {
                        end: (4 + context.measureText(digit).width) * pixels,
                        rows: draw(() => context.fillText(digit, 4, 72)).map(([, right]) => right)
                    };
                }
                scan = {
                    pixels: pixels,
                    digitsWidth: context.measureText(reading.digits).width,
                    baseline: baseline,
                    glyphs: glyphs,
                    degree: {
                        left: Math.min(...signRows.map(y => sign[y][0])) - 4 * pixels,
                        top: signRows[0] - baseline,
                        bottom: signRows[signRows.length - 1] + 1 - baseline
                    }
                };
            }
        }
    }

    Text {
        id: number
        text: reading.value
        color: reading.color
        font.family: Kirigami.Theme.defaultFont.family
        font.features: ({ "tnum": 1 })
        font.pointSize: reading.pointSize
        textFormat: Text.PlainText
        Accessible.ignored: reading.accessibleIgnored
    }

    Text {
        id: suffix
        visible: text !== ""
        text: reading.degreeUnit === "" ? reading.unit : reading.value === "–" ? "" : "°" + reading.degreeUnit
        anchors.left: number.right
        anchors.leftMargin: reading.unitSpacing + reading.degreeShift
        // Hanging from the digits' top keeps the smaller unit inside the
        // number's line box, so the reading is no taller.
        y: number.baselineOffset - baselineOffset - reading.degreeLift
        color: reading.unitColor
        font.family: Kirigami.Theme.defaultFont.family
        font.features: ({ "tnum": 1 })
        font.pointSize: reading.degreeUnit !== "" ? Kirigami.Theme.smallFont.pointSize
                                                  : Style.unitPointSize(reading.pointSize, Kirigami.Theme.smallFont.pointSize)
        textFormat: Text.PlainText
        Accessible.ignored: reading.accessibleIgnored
    }
}
