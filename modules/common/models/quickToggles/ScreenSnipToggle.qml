import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.core

QuickToggleModel {
    name: Translation.tr("Screen snip")
    hasStatusText: false
    toggled: false
    icon: "screenshot_region"

    mainAction: () => {
        PanelRegistry.close("sidebarRight");
        delayedActionTimer.start();
    }
    Timer {
        id: delayedActionTimer
        interval: 300
        repeat: false
        onTriggered: {
            Quickshell.execDetached(["qs", "-p", Quickshell.shellPath(""), "ipc", "call", "region", "screenshot"]);
        }
    }

    tooltipText: Translation.tr("Screen snip")
}
