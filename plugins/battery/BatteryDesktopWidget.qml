// Desktop widget: a ring, the level, and one line of status.
//
// A ring rather than the bar's capsule because at desktop scale a capsule is a long
// thin bar of colour with nothing in the middle, and the middle is exactly where the
// number wants to be.

import QtQuick
import QtQuick.Layouts
import qs.core
import qs.modules.common.widgets

PluginBackgroundWidget {
    id: root

    pluginId: "battery"
    widgetId: "batteryDesktop"

    readonly property real size: root.settings.desktopSize ?? 140

    implicitWidth: root.size
    implicitHeight: root.size

    // Preserve the base's opacity gate (it hides widgets on the lock screen) while also
    // staying out of the way on a desktop with no battery.
    visible: BatteryState.available && root.opacity > 0

    readonly property color colBattery: BatteryState.accent(Theme.accent)

    // Its own backing, so it stays legible over any wallpaper.
    Rectangle {
        anchors.fill: parent

        radius: Theme.radius.full
        color: Theme.solid
    }

    CircularProgress {
        id: ring

        anchors.centerIn: parent

        implicitSize: root.size - Theme.pad.xl
        lineWidth: Math.max(4, root.size / 16)
        value: BatteryState.level
        colPrimary: root.colBattery
        colSecondary: Theme.fade(root.colBattery, 0.82)
        enableAnimation: true

        Behavior on colPrimary {
            animation: Theme.anim.fast.colorAnimation.createObject(this)
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: -2

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: 0

            MaterialSymbol {
                Layout.alignment: Qt.AlignVCenter

                text: BatteryState.icon()
                visible: text.length > 0
                fill: 1
                iconSize: root.size / 7
                color: root.colBattery
            }

            StyledText {
                text: `${BatteryState.percent}`
                font.pixelSize: root.size / 4
                font.weight: Font.Medium
                color: Theme.text
            }

            StyledText {
                Layout.alignment: Qt.AlignTop
                Layout.topMargin: root.size / 14

                text: "%"
                font.pixelSize: root.size / 9
                color: Theme.fade(Theme.text, 0.35)
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            Layout.maximumWidth: root.size - Theme.pad.xl * 2

            text: BatteryState.summary()
            font.pixelSize: Math.max(Theme.font.xs, root.size / 14)
            color: Theme.fade(Theme.text, 0.35)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }
}
