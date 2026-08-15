import QtQuick
import Quickshell
import qs.modules.common
import ".."

StyledOverlayWidget {
    id: root
    title: "MangoHud FPS"
    minimumWidth: 275
    minimumHeight: 100
    contentItem: FpsLimiterContent {
        radius: root.contentRadius
    }
}
