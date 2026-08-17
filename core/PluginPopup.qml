// Base type for a plugin's hover panel.
//
// Wraps the shell's own popup so a plugin gets the right surface, shadow, corner
// radius, edge placement and open/close animation without knowing any of it, and so
// popups from plugins are indistinguishable from the built-in ones.
//
// Used as the `popup:` of a PluginBarWidget, which wires `hoverTarget` for you:
//
//     PluginBarWidget {
//         popup: Component {
//             PluginPopup {
//                 title: "Battery"
//                 subtitle: BatteryState.summary()
//                 icon: "battery_android_full"
//
//                 PluginRow { label: "Health"; value: "91%" }
//                 PluginRow { label: "Cycles"; value: "142" }
//             }
//         }
//     }
//
// `title`/`subtitle`/`icon` are optional: leave them out and you get a bare panel
// with your content in it. Children go under the header, in a column.

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

StyledPopup {
    id: root

    // Set by PluginBarWidget. Any Item with `containsMouse` works.
    // (declared by StyledPopup)

    // When it closes - `dismiss` from StyledPopup, restated here because it is the one property a
    // plugin author has to think about:
    //
    //     dismiss: "pill"    (default) gone as soon as the pointer leaves the bar widget
    //     dismiss: "popup"   stays while the pointer is on the widget or on the popup
    //     dismiss: "manual"  stays until close() once the pointer has reached it
    //
    // Put anything clickable behind "popup" or "manual". With "pill" the window is destroyed while
    // the pointer is still on its way to the popup, so a button in it cannot be reached - which is
    // exactly what happened to the first popups that had buttons.

    // Optional header.
    property string title: ""
    property string subtitle: ""
    property string icon: ""

    // Tint the header icon, e.g. Theme.errorBlock when something is wrong.
    property color iconBlock: Theme.accentBlock
    property color iconColor: Theme.accent

    // Content goes here, not into StyledPopup's single contentItem.
    default property alias body: bodyColumn.data

    // How wide the panel is allowed to get before text wraps.
    property real maximumWidth: 320

    contentItem: ColumnLayout {
        spacing: Theme.pad.m

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Theme.pad.xs

            spacing: Theme.pad.l
            visible: root.title !== "" || root.subtitle !== "" || root.icon !== ""

            MaterialShapeWrappedMaterialSymbol {
                Layout.alignment: Qt.AlignTop

                visible: root.icon !== ""
                shape: MaterialShape.Shape.ClamShell
                text: root.icon
                iconSize: Theme.font.l
                implicitSize: 38
                color: root.iconBlock
                colSymbol: root.iconColor
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: -2

                StyledText {
                    Layout.fillWidth: true

                    visible: root.title !== ""
                    text: root.title
                    font.pixelSize: Theme.font.m
                    font.weight: Font.Medium
                    color: Theme.textDim
                    elide: Text.ElideRight
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.maximumWidth: root.maximumWidth

                    visible: root.subtitle !== ""
                    text: root.subtitle
                    font.pixelSize: Theme.font.s
                    color: Theme.textFaint
                    wrapMode: Text.Wrap
                }
            }
        }

        ColumnLayout {
            id: bodyColumn

            Layout.fillWidth: true
            Layout.maximumWidth: root.maximumWidth
            spacing: Theme.pad.s
        }
    }
}
