import QtQuick
import org.kde.kirigami as Kirigami

// The small, dim title over a reading: an upper-case label and an optional
// detail that keeps its case, as in "USAGE · 60 s" or "SWAP (zram)".
Text {
    property string label: ""
    property string detail: ""

    text: [label.toLocaleUpperCase(), detail].filter(s => s !== "").join(" ")
    color: Qt.alpha(Kirigami.Theme.textColor, 0.6)
    font.pointSize: Kirigami.Theme.smallFont.pointSize
    textFormat: Text.PlainText
    elide: Text.ElideRight
}
