import QtQuick
import Quickshell
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.core

QuickToggleModel {
    name: Translation.tr("Virtual Keyboard")
    toggled: PanelRegistry.state("onScreenKeyboard").open
    icon: toggled ? "keyboard_hide" : "keyboard"
    
    mainAction: () => {
        PanelRegistry.toggle("onScreenKeyboard")
    }

    tooltipText: Translation.tr("On-screen keyboard")
}
