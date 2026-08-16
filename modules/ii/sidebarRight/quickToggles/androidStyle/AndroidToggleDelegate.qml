// One delegate for every Android-style quick toggle, replacing a DelegateChooser that
// had one branch per toggle - seventeen blocks repeating the same eleven property
// assignments, and no way for a plugin to add an eighteenth, since DelegateChoice
// children have to exist at compile time.
//
// The toggle is resolved by id through QuickToggleRegistry and loaded by URL, so what
// is a built-in and what came from a plugin stops mattering here.
//
// The grid context is pushed in with Bindings rather than read out of the parent,
// which keeps each toggle usable on its own - the classic panel instantiates several
// of them directly.

pragma ComponentBehavior: Bound

import QtQuick
import qs.core

Loader {
    id: root

    required property int index
    required property var modelData

    property int startingIndex: 0
    property bool editMode: false
    property var gridRef: null
    property var dropIndicatorRef: null
    property bool isUnused: false
    required property real baseCellWidth
    required property real baseCellHeight
    required property real spacing

    signal openAudioOutputDialog()
    signal openAudioInputDialog()
    signal openBluetoothDialog()
    signal openNightLightDialog()
    signal openWifiDialog()

    readonly property string toggleId: root.modelData?.type ?? ""

    source: QuickToggleRegistry.androidUrl(root.toggleId)

    // Synchronous on purpose: the row is a layout, and a toggle that arrives a frame
    // late would make the whole panel jump as it reflows.
    asynchronous: false

    // A toggle that cannot be resolved - a stale id in the user's saved layout, or a
    // plugin that has since been removed - loads nothing and takes up no space, rather
    // than leaving a hole in the row. Deliberately no `active` gate here: making it
    // depend on `source` means the Loader never reads `source`, so the binding never
    // evaluates and nothing ever loads.
    visible: root.status === Loader.Ready

    Binding { target: root.item; property: "buttonIndex"; value: root.startingIndex + root.index; when: root.item !== null }
    Binding { target: root.item; property: "buttonData"; value: root.modelData; when: root.item !== null }
    Binding { target: root.item; property: "editMode"; value: root.editMode; when: root.item !== null }
    Binding { target: root.item; property: "gridRef"; value: root.gridRef; when: root.item !== null }
    Binding { target: root.item; property: "dropIndicatorRef"; value: root.dropIndicatorRef; when: root.item !== null }
    Binding { target: root.item; property: "isUnused"; value: root.isUnused; when: root.item !== null }
    Binding { target: root.item; property: "expandedSize"; value: (root.modelData?.size ?? 1) > 1; when: root.item !== null }
    Binding { target: root.item; property: "cellSize"; value: root.modelData?.size ?? 1; when: root.item !== null }
    Binding { target: root.item; property: "baseCellWidth"; value: root.baseCellWidth; when: root.item !== null }
    Binding { target: root.item; property: "baseCellHeight"; value: root.baseCellHeight; when: root.item !== null }
    Binding { target: root.item; property: "cellSpacing"; value: root.spacing; when: root.item !== null }

    onLoaded: {
        if (root.item?.openMenu)
            root.item.openMenu.connect(() => root.dispatchMenu());
    }

    // Which dialog the expand arrow opens is a property of the toggle, declared in the
    // registry, instead of being wired up per branch at the call site.
    function dispatchMenu() {
        switch (QuickToggleRegistry.menuFor(root.toggleId)) {
        case "audioOutput": root.openAudioOutputDialog(); break;
        case "audioInput": root.openAudioInputDialog(); break;
        case "bluetooth": root.openBluetoothDialog(); break;
        case "nightLight": root.openNightLightDialog(); break;
        case "wifi": root.openWifiDialog(); break;
        }
    }
}
