// The window PluginDialogs draws into.
//
// Instantiated once, by PluginHost. There is no plugin behind it on purpose: a dialog that only
// appears when some plugin happens to be enabled would make PluginDialogs.confirm() a coin flip,
// and the whole point of asking for confirmation is that it happens.
//
// Nothing here is plugin-specific; it renders whatever PluginDialogs.current describes.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.core
import qs.modules.common
import qs.modules.common.widgets

Scope {
    id: root

    readonly property var dialog: PluginDialogs.current
    readonly property string kind: root.dialog?.kind ?? ""
    readonly property var options: root.dialog?.options ?? ({})

    LazyLoader {
        activeAsync: PluginDialogs.open

        PanelWindow {
            id: panel

            visible: PluginDialogs.open
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:pluginDialog"
            // Exclusive: a modal question that cannot be answered from the keyboard is not modal,
            // and Escape has to reach it rather than the window underneath.
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            anchors { top: true; left: true; right: true; bottom: true }

            Keys.onEscapePressed: PluginDialogs.cancel()

            // Scrim. Clicking it cancels, which is the convention for a dismissible modal; an
            // alert has nothing to cancel so it just closes.
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.45)

                TapHandler {
                    onTapped: PluginDialogs.cancel()
                }
            }

            Rectangle {
                id: card
                anchors.centerIn: parent
                width: Math.min(420, panel.width - 80)
                implicitHeight: layout.implicitHeight + Theme.pad.xl * 2
                height: implicitHeight
                radius: Appearance.rounding.large
                color: Theme.solid

                // Eats the tap so a click inside the card does not reach the scrim behind it.
                TapHandler {}

                ColumnLayout {
                    id: layout
                    anchors.fill: parent
                    anchors.margins: Theme.pad.xl
                    spacing: Theme.pad.l

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.pad.m

                        MaterialSymbol {
                            visible: (root.options.icon ?? "").length > 0 || root.options.danger === true
                            text: root.options.icon ?? (root.options.danger === true ? "warning" : "help")
                            iconSize: Theme.font.xl
                            color: root.options.danger === true ? Theme.error : Theme.accent
                        }

                        StyledText {
                            Layout.fillWidth: true
                            text: root.options.title ?? ""
                            font.pixelSize: Theme.font.l
                            font.weight: Font.DemiBold
                            color: Theme.text
                            wrapMode: Text.Wrap
                        }
                    }

                    StyledText {
                        Layout.fillWidth: true
                        visible: (root.options.message ?? "").length > 0
                        text: root.options.message ?? ""
                        font.pixelSize: Theme.font.m
                        color: Theme.textDim
                        wrapMode: Text.Wrap
                    }

                    // ------------------------------------------------------------- prompt
                    MaterialTextField {
                        id: input
                        Layout.fillWidth: true
                        visible: root.kind === "prompt"
                        placeholderText: root.options.placeholder ?? ""
                        text: root.options.initial ?? ""
                        onVisibleChanged: if (visible) Qt.callLater(() => { forceActiveFocus(); selectAll(); })
                        Keys.onReturnPressed: PluginDialogs.resolve(input.text)
                        Keys.onEnterPressed: PluginDialogs.resolve(input.text)
                    }

                    // ------------------------------------------------------------- choose
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.kind === "choose"
                        spacing: Theme.pad.xs

                        Repeater {
                            model: root.kind === "choose" ? (root.options.options ?? []) : []

                            delegate: PluginCard {
                                required property var modelData
                                required property int index

                                Layout.fillWidth: true
                                // A choice list is a list of buttons, so each row is its own
                                // answer rather than needing a separate confirm.
                                interactive: true
                                onClicked: PluginDialogs.resolve(index)

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: Theme.pad.m

                                    MaterialSymbol {
                                        visible: typeof modelData === "object" && (modelData.icon ?? "").length > 0
                                        text: typeof modelData === "object" ? (modelData.icon ?? "") : ""
                                        iconSize: Theme.font.l
                                        color: Theme.accent
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: typeof modelData === "object" ? (modelData.label ?? modelData.value ?? "") : `${modelData}`
                                        font.pixelSize: Theme.font.m
                                        color: Theme.text
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                    }

                    // ------------------------------------------------------------ buttons
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: Theme.pad.xs
                        spacing: Theme.pad.s
                        visible: root.kind !== "choose"

                        Item { Layout.fillWidth: true }

                        RippleButton {
                            visible: root.kind !== "alert"
                            buttonText: root.options.cancelText ?? qsTr("Cancel")
                            onClicked: PluginDialogs.cancel()
                        }

                        RippleButton {
                            id: confirmButton
                            buttonText: root.options.confirmText ?? (root.kind === "alert" ? qsTr("OK") : qsTr("Confirm"))
                            colBackground: root.options.danger === true ? Theme.errorBlock : Theme.accentBlock
                            onClicked: {
                                if (root.kind === "prompt")
                                    PluginDialogs.resolve(input.text);
                                else if (root.kind === "alert")
                                    PluginDialogs.resolve(true);
                                else
                                    PluginDialogs.resolve(true);
                            }
                        }
                    }
                }
            }
        }
    }
}
