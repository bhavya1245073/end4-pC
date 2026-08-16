pragma ComponentBehavior: Bound

import qs
import qs.core
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Item {
    id: root
    implicitHeight: col.implicitHeight + 16

    Rectangle {
        anchors.fill: parent
        radius: Appearance.rounding.verylarge
        color: Appearance.colors.colLayer0
    }

    ColumnLayout {
        id: col
        anchors { fill: parent; margins: 8 }
        spacing: 2

        ConfigSwitch {
            Layout.fillWidth: true
            buttonIcon: "lock"
            text: Translation.tr("Lock widget positions")
            checked: Config.options.background.widgetsLocked
            onCheckedChanged: Config.options.background.widgetsLocked = checked
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.topMargin: 4
            Layout.bottomMargin: 4
            implicitHeight: 1
            color: Appearance.colors.colOutlineVariant
            opacity: 0.4
        }

        // Built-ins and plugin widgets in one list, from the one registry that knows
        // they exist. A plugin's desktop widget shows up here without this file
        // knowing anything about it - which is the whole point, because before this
        // the list was hardcoded and plugin widgets could not be reached from the
        // desktop menu at all.
        Repeater {
            model: DesktopWidgetRegistry.all
            delegate: ConfigSwitch {
                required property var modelData
                Layout.fillWidth: true
                buttonIcon: modelData.icon
                text: modelData.name
                // A widget whose plugin is switched off is shown but greyed, rather
                // than vanishing, so the row does not jump around under the cursor.
                enabled: DesktopWidgetRegistry.installed(modelData)
                checked: DesktopWidgetRegistry.enabled(modelData)
                onCheckedChanged: DesktopWidgetRegistry.setEnabled(modelData, checked)
            }
        }
    }
}