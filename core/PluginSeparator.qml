// A hairline between groups of rows.
//
// Deliberately a type rather than a remembered incantation: the opacity and the
// colour role both matter, and a separator drawn at full contrast is the fastest way
// to make a clean panel look cheap.

import QtQuick
import QtQuick.Layouts
import qs.modules.common

Rectangle {
    property bool shown: true

    Layout.fillWidth: true
    Layout.topMargin: Theme.pad.xs
    Layout.bottomMargin: Theme.pad.xs

    implicitHeight: 1
    color: Theme.outline
    opacity: 0.25
    visible: shown
}
