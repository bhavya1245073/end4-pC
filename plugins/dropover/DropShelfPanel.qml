// Draggable DropShelf Panel
//
// A floating, movable shelf for parking files and images between windows.
// Supports native drag-in to park files, drag-out to other apps, and free window repositioning.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.core
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

PanelWindow {
    id: shelfRoot

    visible: PanelRegistry.state("dropover").open
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell:dropshelf"
    color: "transparent"

    // Where it was dropped, from the open request. Defaults to the middle of the screen for an
    // open with no arguments - `qs ipc call dropover show`, for instance.
    readonly property var openArgs: PanelRegistry.state("dropover").args
    property real posX: Math.max(20, (shelfRoot.openArgs.x ?? Screen.width / 2) - implicitWidth / 2)
    property real posY: Math.max(20, (shelfRoot.openArgs.y ?? Screen.height / 2) - implicitHeight - 30)

    anchors { top: true; left: true }
    margins {
        left: shelfRoot.posX
        top: shelfRoot.posY
    }

    implicitWidth: 420
    implicitHeight: shelfBg.implicitHeight

    // Re-anchor to drop location on open
    Connections {
        target: PanelRegistry.state("dropover")
        function onOpenChanged() {
            if (PanelRegistry.state("dropover").open) {
                const args = PanelRegistry.state("dropover").args;
                const wantedX = args.x ?? Screen.width / 2;
                const wantedY = args.y ?? Screen.height / 2;
                shelfRoot.posX = Math.max(20, Math.min(Screen.width - shelfRoot.implicitWidth - 20, wantedX - shelfRoot.implicitWidth / 2));
                shelfRoot.posY = Math.max(20, Math.min(Screen.height - shelfRoot.implicitHeight - 40, wantedY - shelfRoot.implicitHeight - 30));
            }
        }
    }

    StyledRectangularShadow {
        target: shelfBg
    }

    // ── Outer Background & Drop Receiver ──────────────────────────────────────
    Rectangle {
        id: shelfBg
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        implicitHeight: contentColumn.implicitHeight + (Theme.pad.l * 2)

        radius: Theme.radius.l
        color: Theme.solid
        border.width: dropZone.containsDrag ? 2 : 1
        border.color: dropZone.containsDrag ? Theme.accent : Theme.fade(Theme.outline, 0.5)

        Behavior on border.color {
            animation: Theme.anim.fast.colorAnimation.createObject(this)
        }

        // Single root DropArea for receiving files dragged into the shelf
        DropArea {
            id: dropZone
            anchors.fill: parent
            keys: ["text/uri-list"]

            onEntered: (drag) => {
                drag.accepted = drag.hasUrls;
            }

            onDropped: (drop) => {
                if (!drop.hasUrls) {
                    drop.accepted = false;
                    return;
                }
                DropShelfState.addItems(drop.urls);
                drop.accept();
            }
        }

        ColumnLayout {
            id: contentColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.pad.l
            spacing: Theme.pad.m

            // ── Draggable Header Bar ──────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                implicitHeight: headerRow.implicitHeight

                DragHandler {
                    id: windowDragHandle
                    target: null
                    property real startX: 0
                    property real startY: 0

                    onActiveChanged: {
                        if (active) {
                            startX = shelfRoot.posX;
                            startY = shelfRoot.posY;
                        }
                    }

                    onTranslationChanged: {
                        if (!active) return;
                        shelfRoot.posX = Math.max(10, Math.min(Screen.width - shelfRoot.implicitWidth - 10, startX + translation.x));
                        shelfRoot.posY = Math.max(10, Math.min(Screen.height - shelfRoot.implicitHeight - 10, startY + translation.y));
                    }
                }

                RowLayout {
                    id: headerRow
                    anchors.fill: parent
                    spacing: Theme.pad.s

                    // Grip / Move Icon
                    MaterialSymbol {
                        text: "drag_indicator"
                        iconSize: 18
                        color: windowDragHandle.containsMouse ? Theme.accent : Theme.textDim
                    }

                    // Title
                    StyledText {
                        text: qsTr("Drop Shelf")
                        font.pixelSize: Theme.font.m
                        font.weight: Font.DemiBold
                        color: Theme.text
                    }

                    // Count Badge
                    Rectangle {
                        visible: DropShelfState.items.length > 0
                        implicitHeight: 22
                        implicitWidth: countText.implicitWidth + 14
                        radius: Theme.radius.full
                        color: Theme.accentMuted

                        StyledText {
                            id: countText
                            anchors.centerIn: parent
                            text: `${DropShelfState.items.length}`
                            font.pixelSize: Theme.font.xs
                            font.weight: Font.DemiBold
                            color: Theme.onAccentMuted
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Action Buttons
                    RowLayout {
                        spacing: Theme.pad.xs

                        // Copy Button
                        Rectangle {
                            visible: DropShelfState.items.length > 0
                            implicitWidth: 28
                            implicitHeight: 28
                            radius: Theme.radius.full
                            color: copyHov.containsPress ? Theme.fade(Theme.accent, 0.25)
                                 : copyHov.containsMouse ? Theme.fade(Theme.accent, 0.12)
                                 : "transparent"

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "content_copy"
                                iconSize: 15
                                color: copyHov.containsMouse ? Theme.accent : Theme.textDim
                            }
                            HoverHandler { id: copyHov }
                            TapHandler { onTapped: DropShelfState.copyAll() }
                        }

                        // Clear Button
                        Rectangle {
                            visible: DropShelfState.items.length > 0
                            implicitWidth: 28
                            implicitHeight: 28
                            radius: Theme.radius.full
                            color: clearHov.containsPress ? Theme.fade(Theme.accent, 0.25)
                                 : clearHov.containsMouse ? Theme.fade(Theme.accent, 0.12)
                                 : "transparent"

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "delete_sweep"
                                iconSize: 16
                                color: clearHov.containsMouse ? Theme.accent : Theme.textDim
                            }
                            HoverHandler { id: clearHov }
                            TapHandler { onTapped: DropShelfState.clear() }
                        }

                        // Close Button
                        Rectangle {
                            implicitWidth: 28
                            implicitHeight: 28
                            radius: Theme.radius.full
                            color: closeHov.containsPress ? Theme.fade(Theme.accent, 0.25)
                                 : closeHov.containsMouse ? Theme.fade(Theme.accent, 0.12)
                                 : "transparent"

                            MaterialSymbol {
                                anchors.centerIn: parent
                                text: "close"
                                iconSize: 16
                                color: closeHov.containsMouse ? Theme.accent : Theme.textDim
                            }
                            HoverHandler { id: closeHov }
                            TapHandler { onTapped: DropShelfState.hide() }
                        }
                    }
                }
            }

            // ── Parked Files Horizontal Shelf ─────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 120
                visible: DropShelfState.items.length > 0

                ListView {
                    id: fileListView
                    anchors.fill: parent
                    orientation: ListView.Horizontal
                    spacing: 10
                    clip: true
                    model: DropShelfState.items

                    WheelHandler {
                        target: fileListView
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: (event) => {
                            if (event.angleDelta.y < 0 || event.angleDelta.x > 0)
                                fileListView.flick(-400, 0);
                            else
                                fileListView.flick(400, 0);
                        }
                    }

                    delegate: PluginDraggable {
                        id: cardDelegate
                        required property string modelData
                        required property int index

                        width: 110
                        height: 120
                        path: modelData

                        onClicked: {
                            // Single click focuses / activates card without aggressively opening external app
                        }

                        Rectangle {
                            id: cardBg
                            anchors.fill: parent
                            radius: Theme.radius.m
                            color: cardHover.containsMouse ? Theme.top : Theme.raised
                            border.width: 1
                            border.color: cardDelegate.dragging ? Theme.accent : Theme.fade(Theme.outline, 0.4)
                            clip: true

                            Behavior on color {
                                animation: Theme.anim.fast.colorAnimation.createObject(this)
                            }

                            // Image Thumbnail
                            StyledImage {
                                visible: /\.(png|jpe?g|webp|bmp|gif|svg)$/i.test(cardDelegate.path)
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: 80
                                source: "file://" + cardDelegate.path
                                fillMode: Image.PreserveAspectCrop
                                cache: true
                                asynchronous: true
                            }

                            // Non-Image File Icon
                            Item {
                                visible: !/\.(png|jpe?g|webp|bmp|gif|svg)$/i.test(cardDelegate.path)
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: 80

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: cardDelegate.path.endsWith("/") ? "folder" : "draft"
                                    iconSize: 36
                                    color: Theme.accent
                                }
                            }

                            // File Name Caption
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: 40
                                color: Theme.fade(Theme.solid, 0.85)

                                StyledText {
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    text: cardDelegate.path.split("/").filter(Boolean).pop() || "file"
                                    font.pixelSize: Theme.font.xs
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    wrapMode: Text.WrapAnywhere
                                    maximumLineCount: 2
                                    elide: Text.ElideMiddle
                                    color: Theme.text
                                }
                            }

                            // Remove Item Button (hover badge with isolated MouseArea)
                            Rectangle {
                                id: removeBtn
                                visible: cardHover.containsMouse
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 4
                                width: 22
                                height: 22
                                radius: 11
                                color: removeMouse.containsPress ? Theme.error : (removeMouse.containsMouse ? Theme.accentBlock : Theme.solid)
                                border.width: 1
                                border.color: Theme.outlineDim
                                z: 100

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "close"
                                    iconSize: 12
                                    color: removeMouse.containsPress ? "#ffffff" : (removeMouse.containsMouse ? Theme.error : Theme.textDim)
                                }

                                MouseArea {
                                    id: removeMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    propagateComposedEvents: false
                                    preventStealing: true

                                    onClicked: mouse => {
                                        mouse.accepted = true;
                                        DropShelfState.remove(cardDelegate.path);
                                        if (DropShelfState.items.length === 0) {
                                            DropShelfState.hide();
                                        }
                                    }
                                }
                            }
                        }

                        HoverHandler {
                            id: cardHover
                        }
                    }
                }
            }

            // ── Empty State / Drop Hint ───────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 100
                visible: DropShelfState.items.length === 0

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: Theme.pad.s

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: dropZone.containsDrag ? "download" : "move_to_inbox"
                        iconSize: 36
                        color: dropZone.containsDrag ? Theme.accent : Theme.textFaint
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        text: dropZone.containsDrag ? qsTr("Release to park files here") : qsTr("Drop files here to park them")
                        font.pixelSize: Theme.font.s
                        color: dropZone.containsDrag ? Theme.accent : Theme.textFaint
                    }
                }
            }
        }
    }
}