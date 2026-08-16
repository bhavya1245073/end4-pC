import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import "."
import qs.core

Scope {
    id: root

    property Component regionComponent: Component {
        Region {}
    }
    
    Loader {
        id: overlayLoader
        active: PanelRegistry.state("overlay").open || OverlayContext.hasPinnedWidgets
        sourceComponent: PanelWindow {
            id: overlayWindow
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "quickshell:overlay"
            WlrLayershell.layer: WlrLayer.Overlay
            // Use OnDemand for pinned widgets to allow focus switching with mouse clicks
            WlrLayershell.keyboardFocus: PanelRegistry.state("overlay").open ? WlrKeyboardFocus.Exclusive : (OverlayContext.clickableWidgets.length > 0 ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None)
            visible: true
            color: "transparent"

            mask: Region {
                item: PanelRegistry.state("overlay").open ? overlayContent : null
                regions: OverlayContext.clickableWidgets.map((widget) => regionComponent.createObject(this, {
                    item: widget
                }));
            }

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            HyprlandFocusGrab {
                id: grab
                windows: [overlayWindow]
                active: false
                onCleared: () => {
                    if (!active) PanelRegistry.close("overlay");
                }
            }

            Connections {
                target: PanelRegistry.state("overlay")
                function onOpenChanged() {
                    delayedGrabTimer.restart();
                }
            }

            Timer {
                id: delayedGrabTimer
                interval: Appearance.animation.elementMoveFast.duration
                onTriggered: {
                    grab.active = PanelRegistry.state("overlay").open;
                }
            }

            OverlayContent {
                id: overlayContent
                anchors.fill: parent
            }
        }
    }

    IpcHandler {
        target: "overlay"

        function toggle(): void {
            PanelRegistry.toggle("overlay");
        }
    }

    CompositorGlobalShortcut {
        name: "overlayToggle"
        description: "Toggles overlay on press"

        onPressed: {
            PanelRegistry.toggle("overlay");
        }
    }
}
