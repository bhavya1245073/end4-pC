// A surface to put things on: correct tonal colour, radius, padding and an optional
// hover state, so a plugin never hard-codes a background.
//
//     PluginCard {
//         PluginRow { label: "Uptime"; value: DateTime.uptime }
//     }
//
//     PluginCard {
//         interactive: true
//         onClicked: doSomething()
//         StyledText { text: "Tap me"; color: Theme.text }
//     }
//
// Children go into a column with the card's padding already applied. Set `columns`
// above 1 for a grid, or put your own layout inside as the single child.

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root

    default property alias content: body.data

    // Which surface tone. Higher reads as more raised.
    property color surface: Theme.high
    property real padding: Theme.pad.l
    property int columns: 1
    property real spacing: Theme.pad.s

    // Set true to get a hover layer, a pointer cursor and `clicked`.
    property bool interactive: false

    readonly property bool hovered: mouse.containsMouse

    signal clicked

    Layout.fillWidth: true

    implicitWidth: body.implicitWidth + root.padding * 2
    implicitHeight: body.implicitHeight + root.padding * 2

    color: root.surface
    radius: Theme.radius.m

    Behavior on color {
        animation: Theme.anim.fast.colorAnimation.createObject(this)
    }

    StateLayer {
        anchors.fill: parent
        radius: parent.radius
        color: Theme.text
        visible: root.interactive && mouse.containsMouse
        opacity: mouse.containsPress ? Theme.state.press : Theme.state.hover
    }

    MouseArea {
        id: mouse

        anchors.fill: parent
        enabled: root.interactive
        hoverEnabled: root.interactive
        cursorShape: root.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }

    // An interactive card rises a little under the pointer and settles when pressed. Scale rather
    // than a shadow: a layer-shell surface cannot cast one outside its own bounds, so a shadow on a
    // card inside a panel would be clipped, and 1.5% of scale reads as "this responds" without
    // moving neighbours.
    scale: !root.interactive ? 1 : mouse.containsPress ? 0.985 : mouse.containsMouse ? 1.015 : 1
    Behavior on scale {
        NumberAnimation {
            duration: mouse.containsPress ? Theme.motion.instant : Theme.motion.fast
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Theme.motion.spatialFast
        }
    }

    GridLayout {
        id: body

        anchors {
            fill: parent
            margins: root.padding
        }

        columns: root.columns
        rowSpacing: root.spacing
        columnSpacing: root.spacing
    }
}
