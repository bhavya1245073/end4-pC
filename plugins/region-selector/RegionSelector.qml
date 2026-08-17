pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.core

Scope {
    id: root

    function dismiss() {
        PanelRegistry.close("regionSelector")
    }

    property var action: RegionSelection.SnipAction.Copy
    property var selectionMode: RegionSelection.SelectionMode.RectCorners
    
    Variants {
        model: Quickshell.screens
        delegate: Loader {
            id: regionSelectorLoader
            required property var modelData
            active: PanelRegistry.state("regionSelector").open

            sourceComponent: RegionSelection {
                screen: regionSelectorLoader.modelData
                onDismiss: root.dismiss()
                action: root.action
                selectionMode: root.selectionMode
            }
        }
    }

    function screenshot() {
        if (Persistent.states.record.enable) {
            const saveDir = Config.options.screenSnip.savePath !== "" ? Config.options.screenSnip.savePath : "";

            // slurp, then grim, then the clipboard - three argv calls chained through callbacks
            // rather than one shell line with `$(slurp)` inside it. The old form interpolated the
            // save path into a command string, so a directory name with a quote in it broke it, and
            // `cat file | wl-copy` copied the bytes as text/plain rather than as an image.
            PluginUtils.run(["slurp"], (geometry, code) => {
                const region = `${geometry}`.trim();
                if (code !== 0 || region.length === 0)
                    return;   // cancelled with Escape, which is not an error

                if (saveDir === "") {
                    // Straight to the clipboard, through a file so the MIME type can be right.
                    const temporary = `${PluginFs.runtimeDir}/screenshot-${Date.now()}.png`;
                    PluginUtils.run(["grim", "-g", region, temporary], (_out, grimCode) => {
                        if (grimCode !== 0)
                            return;
                        PluginUtils.copyFile(temporary, "image/png");
                        PluginUtils.notify(qsTr("Screenshot copied"), qsTr("Copied to clipboard"), { icon: "image-x-generic" });
                    });
                    return;
                }

                const stamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
                const filePath = `${PluginFs.expand(saveDir)}/screenshot-${stamp}.png`;
                PluginFs.mkdir(saveDir, () => {
                    PluginUtils.run(["grim", "-g", region, filePath], (_out, grimCode) => {
                        if (grimCode !== 0)
                            return;
                        PluginUtils.copyFile(filePath, "image/png");
                        PluginUtils.notify(qsTr("Screenshot saved"), filePath, { icon: "image-x-generic" });
                    });
                });
            });
            return;
        }
        root.action = RegionSelection.SnipAction.Copy
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        PanelRegistry.open("regionSelector")
    }

    function search() {
        root.action = RegionSelection.SnipAction.Search
        if (Config.options.search.imageSearch.useCircleSelection) {
            root.selectionMode = RegionSelection.SelectionMode.Circle
        } else {
            root.selectionMode = RegionSelection.SelectionMode.RectCorners
        }
        PanelRegistry.open("regionSelector")
    }

    function ocr() {
        root.action = RegionSelection.SnipAction.CharRecognition
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        PanelRegistry.open("regionSelector")
    }

    function record() {
        if (Persistent.states.record.enable) {
            Quickshell.execDetached([Directories.recordScriptPath]);
            return;
        }
        root.action = RegionSelection.SnipAction.Record
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        PanelRegistry.open("regionSelector")
    }

    function recordWithSound() {
        if (Persistent.states.record.enable) {
            Quickshell.execDetached([Directories.recordScriptPath]);
            return;
        }
        root.action = RegionSelection.SnipAction.RecordWithSound
        root.selectionMode = RegionSelection.SelectionMode.RectCorners
        PanelRegistry.open("regionSelector")
    }

    IpcHandler {
        target: "region"

        function screenshot() {
            root.screenshot()
        }
        function search() {
            root.search()
        }
        function ocr() {
            root.ocr()
        }
        function record() {
            root.record()
        }
        function recordWithSound() {
            root.recordWithSound()
        }
    }

    CompositorGlobalShortcut {
        name: "regionScreenshot"
        description: "Takes a screenshot of the selected region"
        onPressed: root.screenshot()
    }
    CompositorGlobalShortcut {
        name: "regionSearch"
        description: "Searches the selected region"
        onPressed: root.search()
    }
    CompositorGlobalShortcut {
        name: "regionOcr"
        description: "Recognizes text in the selected region"
        onPressed: root.ocr()
    }
    CompositorGlobalShortcut {
        name: "regionRecord"
        description: "Records the selected region"
        onPressed: root.record()
    }
    CompositorGlobalShortcut {
        name: "regionRecordWithSound"
        description: "Records the selected region with sound"
        onPressed: root.recordWithSound()
    }
}