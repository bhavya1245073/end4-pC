// Base type for a plugin's bar widget.
//
// Handles the two things every bar widget has to get right - sizing itself
// correctly in a horizontal *and* a vertical bar - so a plugin only has to
// describe its content:
//
//     PluginBarWidget {
//         StyledText {
//             text: DateTime.time
//             color: Appearance.colors.colOnLayer1
//         }
//     }
//
// `vertical` and `mirrored` are set by the bar when it loads the widget.
//
// Content must size itself (a StyledText, a RowLayout, a Rectangle with
// implicitWidth...). Don't anchor it to fill this item, or its size and the
// widget's will chase each other.

import QtQuick
import qs.modules.common

Item {
    id: root

    // Set by the bar. Lay content out along the bar when vertical.
    property bool vertical: false
    property bool mirrored: false

    readonly property bool isMaterial: Config.options.bar.cornerStyle === 3

    // Space around the content, along the bar's long axis.
    property real padding: root.isMaterial ? 4 : 8

    default property alias content: contentHolder.data

    implicitWidth: root.vertical ? Appearance.sizes.verticalBarWidth : contentHolder.width + root.padding * 2
    implicitHeight: root.vertical ? contentHolder.height + root.padding * 2 : Appearance.sizes.barHeight

    Item {
        id: contentHolder
        anchors.centerIn: parent
        width: childrenRect.width
        height: childrenRect.height
    }
}
