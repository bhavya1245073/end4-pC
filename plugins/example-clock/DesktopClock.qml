// Desktop widget of the example-clock plugin.
//
// PluginBackgroundWidget makes it draggable and remembers where it was dropped
// (in plugins.json, under this plugin's "widgets" section). Toggle it from
// Settings -> Desktop -> Widgets -> From plugins.

import QtQuick
import QtQuick.Layouts
import qs.core
import qs.modules.common
import qs.modules.common.widgets

PluginBackgroundWidget {
    id: root

    pluginId: "example-clock"
    widgetId: "exampleDesktopClock"

    implicitWidth: column.implicitWidth + 40
    implicitHeight: column.implicitHeight + 32

    property date now: new Date()

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.large
        color: Appearance.colors.colLayer0
        opacity: 0.65
    }

    ColumnLayout {
        id: column
        anchors.centerIn: parent
        spacing: 0

        StyledText {
            Layout.alignment: root.settings.alignment === "left" ? Qt.AlignLeft : root.settings.alignment === "right" ? Qt.AlignRight : Qt.AlignHCenter
            text: Qt.formatDateTime(root.now, root.settings.format ?? "hh:mm ap")
            font.pixelSize: root.settings.desktopFontSize ?? 48
            font.weight: Font.Medium
            color: root.colText
        }

        StyledText {
            Layout.alignment: root.settings.alignment === "left" ? Qt.AlignLeft : root.settings.alignment === "right" ? Qt.AlignRight : Qt.AlignHCenter
            visible: root.settings.showDate ?? false
            text: Qt.formatDate(root.now, "dddd, d MMMM yyyy")
            font.pixelSize: Appearance.font.pixelSize.normal
            color: root.colText
        }
    }
}
