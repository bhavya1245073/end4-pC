// Desktop widget: a ring gauge with the level in the middle.
//
// Everything is sized from one number (`diameter`) so the layout cannot overflow the
// card the way a hand-tuned version does. The first draft set font sizes as fractions
// of the widget size and put an icon, the number and a "%" in one row - which ran off
// the edge as soon as the level hit three digits.

import QtQuick
import QtQuick.Layouts
import qs.core
import qs.modules.common
import qs.modules.common.widgets

PluginBackgroundWidget {
    id: root

    pluginId: "battery"
    widgetId: "batteryDesktop"

    // Preserve the base's opacity gate (it hides widgets on the lock screen) while also
    // staying out of the way on a desktop with no battery.
    visible: BatteryState.available && root.opacity > 0

    readonly property real diameter: Math.max(120, root.settings.desktopSize ?? 168)
    readonly property real ringWidth: Math.max(6, root.diameter / 14)
    readonly property real inner: root.diameter - root.ringWidth * 4

    implicitWidth: root.diameter
    implicitHeight: root.diameter

    readonly property color colBattery: BatteryState.accent(Theme.accent)

    // Opaque, so the number stays legible over any wallpaper. Circular rather than a
    // rounded square: the ring is the shape of the widget, and a square behind a circle
    // leaves four corners of dead colour.
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Theme.solid
    }

    CircularProgress {
        anchors.centerIn: parent

        implicitSize: root.diameter - root.ringWidth
        lineWidth: root.ringWidth
        value: BatteryState.level
        colPrimary: root.colBattery
        colSecondary: Theme.fade(root.colBattery, 0.85)
        enableAnimation: true

        Behavior on colPrimary {
            animation: Theme.anim.fast.colorAnimation.createObject(this)
        }
    }

    // Constrained to the ring's inner circle, so long text shrinks or elides instead of
    // spilling over the gauge.
    ColumnLayout {
        anchors.centerIn: parent
        width: root.inner
        spacing: 0

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: root.diameter / 40

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter

                text: BatteryState.icon()
                visible: text.length > 0
                fill: 1
                iconSize: root.diameter / 8
                color: root.colBattery
            }

            StyledText {
                text: `${BatteryState.percent}%`
                font.pixelSize: root.diameter / 4.4
                font.weight: Font.Medium
                color: Theme.text
                // Shrinks rather than clips if the icon and three digits together are
                // wider than the inner circle.
                fontSizeMode: Text.HorizontalFit
                minimumPixelSize: Math.round(root.diameter / 9)
                Layout.maximumWidth: root.inner - (root.diameter / 8) - (root.diameter / 40)
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: root.inner
            Layout.topMargin: -root.diameter / 60

            text: BatteryState.summary()
            visible: text.length > 0
            font.pixelSize: Math.max(Theme.font.xs, root.diameter / 15)
            color: Theme.fade(Theme.text, 0.4)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }
}
