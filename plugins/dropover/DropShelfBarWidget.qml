import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core
import qs.modules.common
import qs.modules.common.widgets
import "."

PluginBarWidget {
    id: root

    pluginId: "dropover"
    tooltip: DropShelfState.count > 0 
        ? qsTr("Drop Shelf: %1 item(s) parked (Click to toggle)").arg(DropShelfState.count)
        : qsTr("Drop Shelf: drag files here to park (Click to open)")

    onClicked: {
        PanelRegistry.toggle("dropover");
    }

    // Direct DropArea on top bar pill
    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]

        onEntered: drag => {
            drag.accepted = drag.hasUrls;
        }

        onDropped: drop => {
            if (!drop.hasUrls) {
                drop.accepted = false;
                return;
            }
            DropShelfState.addItems(drop.urls);
            PanelRegistry.open("dropover", ({ x: root.mapToItem(null, 0, 0).x, y: 50 }));
            drop.accept();
        }
    }

    Row {
        spacing: Theme.pad.xs
        layoutDirection: root.mirrored ? Qt.RightToLeft : Qt.LeftToRight

        MaterialSymbol {
            anchors.verticalCenter: parent.verticalCenter
            text: DropShelfState.count > 0 ? "move_to_inbox" : "inbox"
            iconSize: Theme.font.m
            color: DropShelfState.count > 0 ? root.colAccent : root.colTextDim

            Behavior on color {
                animation: Theme.anim.fast.colorAnimation.createObject(this)
            }
        }

        // Count Badge
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: DropShelfState.count > 0
            implicitWidth: countText.implicitWidth + 10
            implicitHeight: 18
            radius: Theme.radius.full
            color: root.colAccent

            StyledText {
                id: countText
                anchors.centerIn: parent
                text: `${DropShelfState.count}`
                font.pixelSize: Theme.font.xs - 2
                font.weight: Font.Bold
                color: Theme.solid
            }
        }
    }
}
