pragma ComponentBehavior: Bound
import qs
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.core

Scope {
    id: root

    function dismiss() {
        PanelRegistry.close("screenTranslator")
    }

    readonly property var currentScreen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? null
    
    Loader {
        id: translatorLoader
        property var lockedScreen
        active: false
        Connections {
            target: PanelRegistry.state("screenTranslator")
            function onOpenChanged() {
                if (!PanelRegistry.state("screenTranslator").open) {
                    translatorLoader.active = false;
                } else {
                    translatorLoader.lockedScreen = root.currentScreen
                    translatorLoader.active = true
                }
            }
        }

        sourceComponent: ScreenTranslatorPanel {
            screen: translatorLoader.lockedScreen
            onDismiss: root.dismiss()
        }
    }

    function translate() {
        PanelRegistry.open("screenTranslator")
    }

    IpcHandler {
        target: "screenTranslator"

        function translate() {
            root.translate()
        }
    }

    CompositorGlobalShortcut {
        name: "screenTranslate"
        description: "Translates screen content"
        onPressed: root.translate()
    }
}
