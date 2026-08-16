import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.core

QuickToggleModel {
    name: Translation.tr("Color picker")
    hasStatusText: false
    toggled: false
    icon: "colorize"

    mainAction: () => {
        PanelRegistry.close("sidebarRight");
        delayedActionTimer.start();
    }
    Timer {
        id: delayedActionTimer
        interval: 300
        repeat: false
        onTriggered: {
            Quickshell.execDetached(["hyprpicker", "-a"]);
        }
    }

    tooltipText: Translation.tr("Color picker")
}
