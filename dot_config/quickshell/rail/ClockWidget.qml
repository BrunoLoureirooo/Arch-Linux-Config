// Rail clock (render .clk): big `HH:mm` in a1 with the small dim timezone
// abbreviation on its baseline, then the date `FRI OCT 23 2026` dim. The render uses
// VT323 for the digits; it is not installed here, so Theme.font bold at the render's
// 3.7em stands in. The time comes from the shared Clock service (not SystemClock).
import QtQuick
import QtQuick.Layouts
import qs
import qs.services

ColumnLayout {
    id: root

    property real px: Theme.px

    spacing: 0

    Row {
        spacing: Math.round(root.px * 3.7 * 0.2)

        Text {
            id: digits
            text: Qt.formatDateTime(Clock.date, "HH:mm")
            color: Theme.a1
            font.family: Theme.font
            font.pixelSize: Math.round(root.px * 3.7)
            font.bold: true
        }

        Text {
            anchors.baseline: digits.baseline
            text: Qt.locale("C").toString(Clock.date, "t")
            color: Theme.dim
            font.family: Theme.font
            font.pixelSize: Math.round(root.px * 3.7 * 0.3)
            font.letterSpacing: root.px * 3.7 * 0.3 * 0.1
        }
    }

    Text {
        // The render's order (as in the bar); C locale so names stay English.
        text: Qt.locale("C").toString(Clock.date, "ddd MMM dd yyyy").toUpperCase()
        color: Theme.dim
        font.family: Theme.font
        font.pixelSize: root.px
    }
}
