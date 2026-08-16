import qs
import qs.core
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property string protectionMessage: ""
    property var focusedScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name)

    // Which indicator to show, and the list of them, both live in OsdRegistry - so a
    // plugin can contribute a HUD of its own (`provides.osdIndicators`) and show it with
    // `OsdRegistry.show("id")`. This panel owns the window, placement and timeout; an
    // indicator only draws content.
    readonly property string currentIndicator: OsdRegistry.current

    // Built-in indicator paths are relative to this file, and a Loader resolves a
    // relative source against the file it appears in - which is this one, wherever the
    // registry happens to live.
    Component.onCompleted: OsdRegistry.builtinBase = Qt.resolvedUrl(".").toString().replace(/\/$/, "")

    Connections {
        target: OsdRegistry

        function onRequested(id, timeout) {
            root.triggerOsd(timeout);
        }
    }

    function triggerOsd(timeout) {
        PanelRegistry.open("onScreenDisplay");
        // An indicator may ask for longer than the user's default - a pomodoro chime wants
        // a few seconds, a volume nudge does not. Held in a property rather than assigned
        // to the Timer, because assigning `interval` would break its binding to the
        // configured value for the rest of the session.
        root.timeoutOverride = timeout ?? 0;
        osdTimeout.restart();
    }

    property int timeoutOverride: 0

    Timer {
        id: osdTimeout
        interval: root.timeoutOverride > 0 ? root.timeoutOverride : Config.options.osd.timeout
        repeat: false
        running: false
        onTriggered: {
            PanelRegistry.close("onScreenDisplay");
            root.protectionMessage = "";
        }
    }

    Connections {
        target: Brightness
        function onBrightnessChanged() {
            root.protectionMessage = "";
            OsdRegistry.show("brightness");
        }
    }

    Connections {
        target: Hyprsunset
        function onGammaChangeAttempt() {
            root.protectionMessage = "";
            OsdRegistry.show("gamma");
        }
    }

    Connections {
        // Listen to volume changes
        target: Audio.sink?.audio ?? null
        function onVolumeChanged() {
            if (!Audio.ready)
                return;
            OsdRegistry.show("volume");
        }
        function onMutedChanged() {
            if (!Audio.ready)
                return;
            OsdRegistry.show("volume");
        }
    }

    Connections {
        // Listen to protection triggers
        target: Audio
        function onSinkProtectionTriggered(reason) {
            root.protectionMessage = reason;
            OsdRegistry.show("volume");
        }
    }

    Loader {
        id: osdLoader
        active: PanelRegistry.state("onScreenDisplay").open

        sourceComponent: PanelWindow {
            id: osdRoot
            color: "transparent"

            Connections {
                target: root
                function onFocusedScreenChanged() {
                    osdRoot.screen = root.focusedScreen;
                }
            }

            WlrLayershell.namespace: "quickshell:onScreenDisplay"
            WlrLayershell.layer: WlrLayer.Overlay
            anchors {
                top: !Config.options.bar.bottom
                bottom: Config.options.bar.bottom
            }
            mask: Region {
                item: osdValuesWrapper
            }

            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            margins {
                top: Appearance.sizes.barHeight
                bottom: Appearance.sizes.barHeight
            }

            implicitWidth: columnLayout.implicitWidth
            implicitHeight: columnLayout.implicitHeight
            visible: osdLoader.active

            ColumnLayout {
                id: columnLayout
                anchors.horizontalCenter: parent.horizontalCenter

                Item {
                    id: osdValuesWrapper
                    // Extra space for shadow
                    implicitHeight: contentColumnLayout.implicitHeight
                    implicitWidth: contentColumnLayout.implicitWidth
                    clip: true

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: PanelRegistry.close("onScreenDisplay")
                    }

                    Column {
                        id: contentColumnLayout
                        anchors {
                            top: parent.top
                            left: parent.left
                            right: parent.right
                        }
                        spacing: 0

                        Loader {
                            id: osdIndicatorLoader
                            source: OsdRegistry.urlFor(root.currentIndicator)
                        }

                        Item {
                            id: protectionMessageWrapper
                            anchors.horizontalCenter: parent.horizontalCenter
                            implicitHeight: protectionMessageBackground.implicitHeight
                            implicitWidth: protectionMessageBackground.implicitWidth
                            opacity: root.protectionMessage !== "" ? 1 : 0

                            StyledRectangularShadow {
                                target: protectionMessageBackground
                            }
                            Rectangle {
                                id: protectionMessageBackground
                                anchors.centerIn: parent
                                color: Appearance.m3colors.m3error
                                property real padding: 10
                                implicitHeight: protectionMessageRowLayout.implicitHeight + padding * 2
                                implicitWidth: protectionMessageRowLayout.implicitWidth + padding * 2
                                radius: Appearance.rounding.normal

                                RowLayout {
                                    id: protectionMessageRowLayout
                                    anchors.centerIn: parent
                                    MaterialSymbol {
                                        id: protectionMessageIcon
                                        text: "dangerous"
                                        iconSize: Appearance.font.pixelSize.hugeass
                                        color: Appearance.m3colors.m3onError
                                    }
                                    StyledText {
                                        id: protectionMessageTextWidget
                                        horizontalAlignment: Text.AlignHCenter
                                        color: Appearance.m3colors.m3onError
                                        wrapMode: Text.Wrap
                                        text: root.protectionMessage
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "osdVolume"

        function trigger() {
            root.triggerOsd();
        }

        function hide() {
            PanelRegistry.close("onScreenDisplay");
        }

        function toggle() {
            PanelRegistry.state("onScreenDisplay").open = !PanelRegistry.state("onScreenDisplay").open;
        }
    }
    CompositorGlobalShortcut {
        name: "osdVolumeTrigger"
        description: "Triggers volume OSD on press"

        onPressed: {
            root.triggerOsd();
        }
    }
    CompositorGlobalShortcut {
        name: "osdVolumeHide"
        description: "Hides volume OSD on press"

        onPressed: {
            PanelRegistry.close("onScreenDisplay");
        }
    }
}
