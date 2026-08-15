// Bar widget of the example-clock plugin.
//
// Everything the user can change comes from `settings`, which is this plugin's
// section of ~/.config/illogical-impulse/plugins.json, with the defaults from
// manifest.json filled in.

import QtQuick
import QtQuick.Layouts
import qs.core
import qs.modules.common
import qs.modules.common.widgets

PluginBarWidget {
    id: root

    readonly property var settings: PluginConfig.of("example-clock")
    property date now: new Date()

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    GridLayout {
        // One column when the bar is vertical, one row when it isn't.
        columns: root.vertical ? 1 : 2
        rowSpacing: 0
        columnSpacing: 6

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDateTime(root.now, root.settings.format ?? "hh:mm ap")
            font.pixelSize: root.vertical ? Appearance.font.pixelSize.small : Appearance.font.pixelSize.normal
            color: root.isMaterial ? Appearance.colors.colOnSecondaryContainer : Appearance.colors.colOnLayer1
        }

        StyledText {
            Layout.alignment: Qt.AlignHCenter
            visible: root.settings.showDate ?? false
            text: Qt.formatDate(root.now, root.vertical ? "MM/dd" : "ddd d MMM")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }
}
