// SPDX-FileCopyrightText: 2026 Emily Hamedian <me@emily.dev>
// SPDX-License-Identifier: GPL-3.0-or-later

pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Shapes
import org.kde.kirigami as Kirigami
import "code/items.js" as Items
import "code/marks.js" as Marks
import "code/style.js" as Style

// An item's name inside its ring: CPU, GPU or MEM, or the Claude or Codex
// mark. It sits in the clear middle, inside the inner ring when one is drawn,
// the name shrinking to fit. Where even its smallest readable size would not
// fit, or the caller turns it off, it is left out; the tooltip and the popup
// still name the item.
Item {
    id: name

    required property string item
    // RingGauge.centreWidth: the clear width inside the innermost ring.
    required property real room
    // Scales the name's font. The package never sets it: the tests do, to
    // stand in for Breeze's 8 pt small font with their own theme's larger one.
    property real sizeFactor: 1
    property bool active: true

    readonly property bool usage: Items.isUsage(item)
    readonly property real minimumPointSize: Kirigami.Theme.smallFont.pointSize * 0.7 * sizeFactor
    // The middle is round, so a name's ink has less room than the middle's
    // width: only the chord at its cap height.
    readonly property real chord: 2 * Math.sqrt(Math.max(0, room * room / 4 - smallest.tightBoundingRect.height ** 2 / 4))
    // A little taller than a name's line, so a mark fills its ring about as
    // much as CPU or MEM fill theirs, kept a pixel clear of the innermost
    // ring, and none at all where there is no room.
    readonly property real markSize: Math.max(0, Math.min(Math.round(nameFont.height * 1.2), Math.floor(room) - 2))
    readonly property bool fits: usage ? markSize >= Kirigami.Units.iconSizes.small / 2 && markSize <= room
                                       : smallest.advanceWidth <= chord

    anchors.fill: parent
    visible: active && fits
    // The cell's description names the item.
    Accessible.ignored: true

    FontMetrics {
        id: nameFont
        font: label.font
    }

    TextMetrics {
        id: smallest
        font.pointSize: name.minimumPointSize
        font.letterSpacing: label.font.letterSpacing
        text: label.text
    }

    // The mark, drawn as a path like the rings, so it sits on their centre
    // whatever the device pixel grid: an icon texture is snapped to whole
    // device pixels, up to half a pixel away. Only Claude and Codex load it;
    // a system ring has no mark to parse. The Loader is left unsized, since a
    // sized one resizes what it loads to itself.
    Loader {
        active: name.usage

        sourceComponent: Shape {
            id: mark

            // Names the mark for the tests, which can't read a path.
            readonly property string markName: name.item
            readonly property var art: name.item === "claude" ? Marks.CLAUDE : Marks.OPENAI
            // Scene pixels per viewBox unit.
            readonly property real unit: name.markSize / art.box[2]

            // The viewBox's middle lands on the ring's.
            x: name.width / 2 - (art.box[0] + art.box[2] / 2) * unit
            y: name.height / 2 - (art.box[1] + art.box[2] / 2) * unit
            width: name.markSize
            height: name.markSize
            preferredRendererType: Shape.CurveRenderer
            transform: Scale { xScale: mark.unit; yScale: mark.unit }

            ShapePath {
                // The names' tone, so the mark reads as one of them.
                fillColor: Style.dim(Kirigami.Theme.textColor)
                strokeColor: "transparent"
                fillRule: ShapePath.WindingFill
                PathSvg { path: mark.art.path }
            }
        }
    }

    // The size HorizontalFit settles on, to set the name by its capitals.
    FontMetrics {
        id: fitted
        font.family: label.font.family
        font.pixelSize: Math.max(1, label.fontInfo.pixelSize)
    }

    TextMetrics {
        id: capSample
        font: fitted.font
        text: "H"
    }

    // capitalHeight needs Qt 6.9; the ink of "H" stands in before that.
    readonly property real capHeight: fitted.capitalHeight ?? capSample.tightBoundingRect.height // qmllint disable missing-property

    // Laid out across the chord, so it shrinks to fit, and set so that the
    // capitals' middle sits at the centre, not the line box's, which is
    // taller below the baseline than above the capitals, and without the
    // letter space after the last glyph, which centring the advance counts.
    // Placed by x and y, not anchors, which round an odd width to a whole
    // pixel.
    Text {
        id: label
        visible: !name.usage
        width: name.chord
        x: (name.width - width) / 2 + font.letterSpacing / 2
        y: name.height / 2 + name.capHeight / 2 - baselineOffset
        horizontalAlignment: Text.AlignHCenter
        text: name.item === "cpu" ? i18nc("@label ring name, at most 3 characters, short for processor", "CPU")
            : name.item === "gpu" ? i18nc("@label ring name, at most 3 characters, short for graphics card", "GPU")
            : i18nc("@label ring name, at most 3 characters, short for memory", "MEM")
        color: Style.dim(Kirigami.Theme.textColor)
        font.pointSize: Kirigami.Theme.smallFont.pointSize * 0.95 * name.sizeFactor
        font.letterSpacing: Kirigami.Theme.smallFont.pointSize * 0.08 * name.sizeFactor
        fontSizeMode: Text.HorizontalFit
        minimumPointSize: Math.floor(name.minimumPointSize)
        textFormat: Text.PlainText
    }
}
