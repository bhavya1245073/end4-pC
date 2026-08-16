import QtQuick
import Quickshell
import qs.core
import qs.modules.common.widgets.widgetCanvas

Scope {
    PluginModuleAnchors {}
    Component.onCompleted: PluginRegistry.discovered
    property int done: 0
    property int total: 0

    Variants {
        model: [1]
        PanelWindow {
            visible: true
            implicitWidth: 1920; implicitHeight: 1080
            color: "transparent"
            WidgetCanvas {
                id: canvas
                anchors.fill: parent
                wallpaperSafetyTriggered: false
                Repeater {
                    id: rep
                    model: []
                    delegate: Loader {
                        required property var modelData
                        asynchronous: false
                        source: modelData.url
                        onStatusChanged: {
                            if (status === Loader.Ready)
                                console.log(`PROBE|OK    ${modelData.id}  ${Math.round(item?.implicitWidth ?? 0)}x${Math.round(item?.implicitHeight ?? 0)}`);
                            else if (status === Loader.Error)
                                console.log(`PROBE|FAIL  ${modelData.id}  ${sourceComponent?.errorString?.() ?? "error"}`);
                        }
                    }
                }
                Timer {
                    interval: 2500; running: true
                    onTriggered: { rep.model = DesktopWidgetRegistry.all; fin.start() }
                }
                Timer { id: fin; interval: 4000; onTriggered: console.log("PROBE|DONE") }
            }
        }
    }
}
