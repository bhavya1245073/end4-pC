import qs.modules.common.widgets
import qs
import qs.services
import QtQuick
import Quickshell.Io
import Quickshell
import qs.core

QuickToggleButton {
    id: root
    visible: EasyEffects.available
    toggled: EasyEffects.active
    buttonIcon: "instant_mix"

    Component.onCompleted: {
        EasyEffects.fetchActiveState()
    }

    onClicked: {
        EasyEffects.toggle()
    }

    altAction: () => {
        Quickshell.execDetached(["bash", "-c", "flatpak run com.github.wwmm.easyeffects || easyeffects"])
        PanelRegistry.close("sidebarRight")
    }

    StyledToolTip {
        text: Translation.tr("EasyEffects | Right-click to configure")
    }
}
