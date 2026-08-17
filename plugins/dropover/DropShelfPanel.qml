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

    readonly property var openArgs: PanelRegistry.state("dropover").args
    property real posX: Math.max(20, (shelfRoot.openArgs.x ?? Screen.width / 2) - implicitWidth / 2)
    property real posY: Math.max(20, (shelfRoot.openArgs.y ?? Screen.height / 2) - implicitHeight - 30)

    anchors { top: true; left: true }
    margins {
        left: shelfRoot.posX
        top: shelfRoot.posY
    }

    // Adaptive width: shrinks snugly around 1 or 2 items, expands for more!
    readonly property int itemCount: DropShelfState.items.length
    readonly property real targetWidth: itemCount === 0 ? 270
        : itemCount === 1 ? 220
        : itemCount === 2 ? 310
        : Math.min(Screen.width - 40, (itemCount * 130) + 40)

    implicitWidth: shelfRoot.targetWidth
    implicitHeight: shelfBg.implicitHeight + (Appearance.sizes.elevationMargin * 2)

    Behavior on implicitWidth {
        NumberAnimation { duration: 250; easing.type: Easing.OutCubic }
    }

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
        anchors.margins: Appearance.sizes.elevationMargin
        implicitHeight: contentColumn.implicitHeight + (Theme.pad.m * 2)

        radius: Appearance.rounding.large
        color: Appearance.colors.colSecondaryContainer
        border.width: dropZone.containsDrag ? 2 : 1
        border.color: dropZone.containsDrag ? Appearance.colors.colPrimary : Theme.fade(Theme.outline, 0.25)
        clip: true

        Behavior on border.color {
            ColorAnimation { duration: 200 }
        }

        // Root DropArea for receiving files dragged into the shelf
        DropArea {
            id: dropZone
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
                drop.accept();
            }
        }

        ColumnLayout {
            id: contentColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Theme.pad.m
            spacing: Theme.pad.s

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
                    spacing: 6

                    // Grip Handle
                    MaterialSymbol {
                        text: "drag_indicator"
                        iconSize: 18
                        color: windowDragHandle.active ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                    }

                    // Title
                    StyledText {
                        text: qsTr("Drop Shelf")
                        font.pixelSize: Theme.font.m
                        font.weight: Font.Bold
                        color: Appearance.colors.colOnSecondaryContainer
                    }

                    // Count Badge
                    Rectangle {
                        visible: DropShelfState.items.length > 0
                        implicitHeight: 20
                        implicitWidth: countText.implicitWidth + 12
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colPrimaryContainer

                        StyledText {
                            id: countText
                            anchors.centerIn: parent
                            text: `${DropShelfState.items.length}`
                            font.pixelSize: Theme.font.xs - 1
                            font.weight: Font.Bold
                            color: Appearance.colors.colOnPrimaryContainer
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Action Buttons Capsule
                    Rectangle {
                        implicitHeight: 30
                        implicitWidth: actionRow.implicitWidth + 6
                        radius: Appearance.rounding.full
                        color: Appearance.colors.colLayer1

                        RowLayout {
                            id: actionRow
                            anchors.centerIn: parent
                            spacing: 2

                            // Copy All
                            Rectangle {
                                visible: DropShelfState.items.length > 0
                                implicitWidth: 26
                                implicitHeight: 26
                                radius: Appearance.rounding.full
                                color: copyHov.containsMouse ? ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.15) : "transparent"

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "content_copy"
                                    iconSize: 14
                                    color: copyHov.containsMouse ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                }
                                HoverHandler { id: copyHov }
                                TapHandler { onTapped: DropShelfState.copyAll() }
                            }

                            // Clear All
                            Rectangle {
                                visible: DropShelfState.items.length > 0
                                implicitWidth: 26
                                implicitHeight: 26
                                radius: Appearance.rounding.full
                                color: clearHov.containsMouse ? ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.15) : "transparent"

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "delete_sweep"
                                    iconSize: 15
                                    color: clearHov.containsMouse ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                }
                                HoverHandler { id: clearHov }
                                TapHandler { onTapped: DropShelfState.clear() }
                            }

                            // Close Shelf
                            Rectangle {
                                implicitWidth: 26
                                implicitHeight: 26
                                radius: Appearance.rounding.full
                                color: closeHov.containsMouse ? ColorUtils.applyAlpha(Appearance.colors.colPrimary, 0.15) : "transparent"

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "close"
                                    iconSize: 15
                                    color: closeHov.containsMouse ? Appearance.colors.colPrimary : Appearance.colors.colSubtext
                                }
                                HoverHandler { id: closeHov }
                                TapHandler { onTapped: DropShelfState.hide() }
                            }
                        }
                    }
                }
            }

            // ── Parked Files Horizontal Shelf ─────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 124
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
                        onWheel: event => {
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

                        // If only 1 item, expand to fill the snug shelf!
                        width: DropShelfState.items.length === 1 ? (shelfRoot.targetWidth - (Theme.pad.m * 2) - (Appearance.sizes.elevationMargin * 2)) : 124
                        height: 124
                        path: modelData

                        scale: cardHover.containsMouse ? 1.03 : 1.0
                        z: cardHover.containsMouse ? 10 : 1
                        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }

                        Rectangle {
                            id: cardBg
                            anchors.fill: parent
                            radius: Appearance.rounding.medium
                            color: Appearance.colors.colLayer1
                            border.width: cardDelegate.dragging ? 2 : 1
                            border.color: cardDelegate.dragging ? Appearance.colors.colPrimary : cardHover.containsMouse ? Appearance.colors.colPrimary : Theme.fade(Theme.outline, 0.20)
                            clip: true

                            // Image Thumbnail
                            StyledImage {
                                visible: /\.(png|jpe?g|webp|bmp|gif|svg)$/i.test(cardDelegate.path)
                                anchors.top: parent.top
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: 82
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
                                height: 82

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: cardDelegate.path.endsWith("/") ? "folder" : "draft"
                                    iconSize: 36
                                    color: Appearance.colors.colPrimary
                                }
                            }

                            // File Name Caption
                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: 42
                                color: Theme.fade(Appearance.colors.colLayer1, 0.95)

                                StyledText {
                                    anchors.fill: parent
                                    anchors.margins: 4
                                    text: cardDelegate.path.split("/").filter(Boolean).pop() || "file"
                                    font.pixelSize: Theme.font.xs
                                    font.weight: Font.Medium
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    wrapMode: Text.WrapAnywhere
                                    maximumLineCount: 2
                                    elide: Text.ElideMiddle
                                    color: Appearance.colors.colOnLayer1
                                }
                            }

                            // Remove Item Button (Hover Badge)
                            Rectangle {
                                id: removeBtn
                                visible: cardHover.containsMouse
                                anchors.top: parent.top
                                anchors.right: parent.right
                                anchors.margins: 5
                                width: 24
                                height: 24
                                radius: 12
                                color: removeMouse.containsPress ? Appearance.colors.colPrimary : Theme.fade("#000000", 0.65)
                                z: 100

                                MaterialSymbol {
                                    anchors.centerIn: parent
                                    text: "close"
                                    iconSize: 13
                                    color: "#ffffff"
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
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 100
                visible: DropShelfState.items.length === 0
                radius: Appearance.rounding.medium
                color: Theme.fade(Appearance.colors.colLayer1, 0.6)
                border.width: 1
                border.color: dropZone.containsDrag ? Appearance.colors.colPrimary : Theme.fade(Theme.outline, 0.25)

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 4

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignCenter
                        text: dropZone.containsDrag ? "download" : "move_to_inbox"
                        iconSize: 30
                        color: Appearance.colors.colPrimary
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignCenter
                        text: dropZone.containsDrag ? qsTr("Drop to park") : qsTr("Drag & drop files here")
                        font.pixelSize: Theme.font.s
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnSecondaryContainer
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignCenter
                        text: qsTr("Movable shelf")
                        font.pixelSize: Theme.font.xs - 1
                        color: Appearance.colors.colSubtext
                    }
                }
            }
        }
    }
}