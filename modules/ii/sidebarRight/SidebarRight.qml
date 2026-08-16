import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.core

Scope {
    id: root
    property int sidebarWidth: Appearance.sizes.sidebarWidth
    readonly property bool centerOnly: Config.options.bar.layouts.leftLayout.length === 0 && Config.options.bar.layouts.rightLayout.length === 0 && !Config.options.bar.vertical

    PanelWindow {
        id: panelWindow

        readonly property bool animatedEntrance: WM.compositor !== "hyprland"
        property bool reallyVisible: false
        visible: reallyVisible

        Component.onCompleted: reallyVisible = PanelRegistry.state("sidebarRight").open

        Connections {
            target: PanelRegistry.state("sidebarRight")
            function onOpenChanged() {
                if (PanelRegistry.state("sidebarRight").open) {
                    closeAnimTimer.stop();
                    panelWindow.reallyVisible = true;
                } else if (panelWindow.animatedEntrance) {
                    closeAnimTimer.restart();
                } else {
                    panelWindow.reallyVisible = false;
                }
            }
        }

        Timer {
            id: closeAnimTimer
            interval: 150
            onTriggered: panelWindow.reallyVisible = false
        }

        function hide() {
            PanelRegistry.close("sidebarRight");
        }

        onVisibleChanged: {
            if (visible) {
                GlobalFocusGrab.addDismissable(panelWindow);
            } else {
                GlobalFocusGrab.removeDismissable(panelWindow);
            }
        }

        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                panelWindow.hide();
            }
        }

        exclusiveZone: 0
        implicitWidth: sidebarWidth
        WlrLayershell.namespace: "quickshell:sidebarRight"
        WlrLayershell.keyboardFocus: PanelRegistry.state("sidebarRight").open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        anchors {
            top: true
            right: true
            bottom: true
            left: animatedEntrance
        }

        margins {
            top: {
                if (Config.options.bar.bottom) return 0;
                if (Config?.options.bar.autoHide.enable) return 0;
                if (!centerOnly) return 0;
                switch (Config.options.bar.cornerStyle) {
                case 0: return -Appearance.sizes.barHeight;
                case 1: return -Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut;
                case 2: return -Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut;
                case 3: return -Appearance.sizes.barHeight - Appearance.sizes.hyprlandGapsOut;
                default: return 0;
                }
            }
            bottom: {
                if (!Config.options.bar.bottom) return 0;
                if (Config?.options.bar.autoHide.enable) return 0;
                if (!centerOnly) return 0;
                switch (Config.options.bar.cornerStyle) {
                case 0: return -Appearance.sizes.barHeight;
                case 1: return -Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut;
                case 2: return -Appearance.sizes.barHeight + Appearance.sizes.hyprlandGapsOut;
                case 3: return -Appearance.sizes.barHeight - Appearance.sizes.hyprlandGapsOut;
                default: return 0;
                }
            }
        }

        Item {
            anchors.fill: parent

            MouseArea {
                id: outsideClickArea
                anchors.fill: parent
                enabled: panelWindow.animatedEntrance
                visible: panelWindow.animatedEntrance
                onClicked: panelWindow.hide()
            }

            Item {
                id: entranceWrapper
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: sidebarWidth
                clip: true

                readonly property bool open: PanelRegistry.state("sidebarRight").open
                property real cachedParentWidth: sidebarWidth
                readonly property real restX: cachedParentWidth - width
                x: panelWindow.animatedEntrance ? (open ? restX : cachedParentWidth) : restX

                Connections {
                    target: entranceWrapper.parent
                    function onWidthChanged() {
                        if (entranceWrapper.parent.width > 0)
                            entranceWrapper.cachedParentWidth = entranceWrapper.parent.width;
                    }
                }

                Behavior on x {
                    enabled: panelWindow.animatedEntrance
                    NumberAnimation {
                        duration: entranceWrapper.open
                            ? Appearance.animation.sidebarSlideEnter.duration
                            : Appearance.animation.sidebarSlideExit.duration
                        easing.type: entranceWrapper.open
                            ? Appearance.animation.sidebarSlideEnter.type
                            : Appearance.animation.sidebarSlideExit.type
                        easing.bezierCurve: entranceWrapper.open
                            ? Appearance.animation.sidebarSlideEnter.bezierCurve
                            : Appearance.animation.sidebarSlideExit.bezierCurve
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: (mouse) => { mouse.accepted = true }
                    z: -1
                }

                Loader {
                    id: sidebarContentLoader
                    active: panelWindow.reallyVisible || Config?.options.sidebar.keepRightSidebarLoaded
                    anchors {
                        fill: parent
                        margins: Appearance.sizes.hyprlandGapsOut
                        leftMargin: Appearance.sizes.elevationMargin
                    }
                    width: sidebarWidth - Appearance.sizes.hyprlandGapsOut - Appearance.sizes.elevationMargin
                    height: parent.height - Appearance.sizes.hyprlandGapsOut * 2

                    focus: PanelRegistry.state("sidebarRight").open
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            panelWindow.hide();
                        }
                    }

                    sourceComponent: SidebarRightContent {}
                }
            }
        }

        IpcHandler {
            target: "sidebarRight"

            function toggle(): void {
                PanelRegistry.toggle("sidebarRight");
            }

            function close(): void {
                PanelRegistry.close("sidebarRight");
            }

            function open(): void {
                PanelRegistry.open("sidebarRight");
            }
        }

        CompositorGlobalShortcut {
            name: "sidebarRightToggle"
            description: "Toggles right sidebar on press"

            onPressed: {
                PanelRegistry.toggle("sidebarRight");
            }
        }
        CompositorGlobalShortcut {
            name: "sidebarRightOpen"
            description: "Opens right sidebar on press"

            onPressed: {
                PanelRegistry.open("sidebarRight");
            }
        }
        CompositorGlobalShortcut {
            name: "sidebarRightClose"
            description: "Closes right sidebar on press"

            onPressed: {
                PanelRegistry.close("sidebarRight");
            }
        }
    }
}