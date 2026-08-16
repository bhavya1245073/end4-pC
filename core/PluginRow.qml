// A label on the left, a value on the right, correctly coloured and sized.
//
// The single most repeated layout in any status panel, and the one most often got
// slightly wrong: the value column drifts, the label competes with the value for
// emphasis, or a long label pushes the value off the panel.
//
//     PluginRow { label: "Health"; value: "91%" }
//     PluginRow { label: "Draw"; value: "12.4 W"; shown: rateKnown }
//     PluginRow { label: "Profile"; value: "Balanced"; icon: "speed" }
//
// `shown` rather than `visible` so it composes with a layout: set it false and the
// row takes no space, which is what you want for a value the hardware did not report.

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

RowLayout {
    id: root

    required property string label
    property string value: ""
    property string icon: ""

    property bool shown: true

    // Emphasise the value, e.g. Theme.error for something out of range.
    property color valueColor: Theme.textDim

    Layout.fillWidth: true
    spacing: Theme.pad.l
    visible: root.shown

    MaterialSymbol {
        Layout.alignment: Qt.AlignVCenter

        visible: root.icon !== ""
        text: root.icon
        iconSize: Theme.font.m
        color: Theme.textFaint
    }

    StyledText {
        Layout.alignment: Qt.AlignVCenter

        text: root.label
        font.pixelSize: Theme.font.s
        color: Theme.textFaint
    }

    // Pushes the value right and, because it is the only stretching cell, keeps the
    // value flush to the edge no matter how long the label is.
    Item {
        Layout.fillWidth: true
    }

    StyledText {
        Layout.alignment: Qt.AlignVCenter

        text: root.value
        font.pixelSize: Theme.font.s
        font.weight: Font.Medium
        color: root.valueColor
        elide: Text.ElideRight

        Behavior on color {
            animation: Theme.anim.fast.colorAnimation.createObject(this)
        }
    }
}
