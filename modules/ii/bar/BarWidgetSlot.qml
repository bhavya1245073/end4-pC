// One widget in the bar: loaded, mirrored, and reporting its own failure.
//
// This existed nine times inline in BarContent.qml - three layouts times three bar styles -
// each copy repeating the same `onLoaded` mirroring check. Nine copies of four lines is where
// the acceptsMirroring bug lived for a while: two of them had been updated and the rest had
// not, so a widget mirrored correctly in a material bar and not in a segmented one.
//
// It also upgrades every bar widget, built-in or plugin, from a bare Loader to
// PluginErrorBoundary - so a widget that fails to compile shows a small error pill in its place
// instead of a gap in the bar. A gap is indistinguishable from "the widget is not configured",
// which is why broken bar widgets went unnoticed for so long.

import QtQuick
import QtQuick.Layouts
import qs.core
import qs.modules.common

PluginErrorBoundary {
    id: root

    // The widget's registry name, e.g. "clock" or "quoteBar".
    property string widgetName: ""

    // The layout array this widget is in, and its position - together they decide whether the
    // widget's content is mirrored, which is how a pill at the right end of the bar puts its
    // icon on the correct side.
    property var layoutModel: []
    property int layoutIndex: 0

    // Mirroring is resolved by the bar, which knows the layout; passing it in keeps this
    // component from having to know about bar geometry.
    property bool mirrored: false

    pluginId: BarWidgetRegistry.pluginIdOf(root.widgetName) || root.widgetName
    entry: BarWidgetRegistry.url(root.widgetName)
    surface: qsTr("bar widget")

    // A bar is 24-40 px tall: an error card does not fit, an error pill does.
    compact: true

    onLoadedItemChanged: {
        // `acceptsMirroring` rather than a property check: Control has a read-only `mirrored`,
        // so hasOwnProperty("mirrored") is true for widgets that cannot accept one - assigning
        // it then fails at runtime. An explicit marker is the only reliable signal.
        if (root.loadedItem && root.loadedItem.acceptsMirroring === true)
            root.loadedItem.mirrored = root.mirrored;
    }

    onMirroredChanged: {
        if (root.loadedItem && root.loadedItem.acceptsMirroring === true)
            root.loadedItem.mirrored = root.mirrored;
    }
}
