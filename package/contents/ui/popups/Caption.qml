import QtQuick
import org.kde.kirigami as Kirigami

// The small, dim, upper-case title over a reading.
Text {
    color: Qt.alpha(Kirigami.Theme.textColor, 0.6)
    font.pointSize: Kirigami.Theme.smallFont.pointSize
    font.capitalization: Font.AllUppercase
    textFormat: Text.PlainText
    elide: Text.ElideRight
}
