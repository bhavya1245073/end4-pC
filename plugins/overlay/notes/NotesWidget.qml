// Named NotesWidget, not Notes, because `services/Notes.qml` is a singleton of
// that name. Two types called Notes, one of them a singleton, resolve to whichever
// the engine happened to bind the name to first, and the loser fails with
// "qmldir defines type as singleton, but no pragma Singleton found". That made the
// whole overlay plugin fail to load, but only in the real shell's load order.

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.services
import qs.modules.common
import ".."

StyledOverlayWidget {
    id: root
    title: Translation.tr("Notes")
    showCenterButton: true

    contentItem: NotesContent {
        radius: root.contentRadius
        isClickthrough: root.clickthrough
    }
}
