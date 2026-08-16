import qs.core
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth

AbstractQuickPanel {
    id: root
    Layout.alignment: Qt.AlignHCenter
    implicitWidth: buttonGroup.implicitWidth
    implicitHeight: buttonGroup.implicitHeight
    color: "transparent"

    ButtonGroup {
        id: buttonGroup
        spacing: 5
        padding: 5
        color: Appearance.colors.colLayer1

        // Was seven statically declared toggles, which meant this panel silently
        // ignored every toggle that was not one of those seven - including anything a
        // plugin contributed. It now renders whatever the registry says has a classic
        // version, in registry order.
        Repeater {
            model: QuickToggleRegistry.availableFor("classic")

            delegate: Loader {
                id: toggleLoader

                required property var modelData

                source: toggleLoader.modelData.classic

                // The classic toggles take an `altAction` callback rather than emitting
                // a signal, so the dialog a toggle opens is applied after it loads.
                onLoaded: {
                    if (!("altAction" in toggleLoader.item))
                        return;
                    switch (toggleLoader.modelData.menu) {
                    case "wifi":
                        toggleLoader.item.altAction = () => root.openWifiDialog();
                        break;
                    case "bluetooth":
                        toggleLoader.item.altAction = () => root.openBluetoothDialog();
                        break;
                    case "nightLight":
                        toggleLoader.item.altAction = () => root.openNightLightDialog();
                        break;
                    case "audioOutput":
                        toggleLoader.item.altAction = () => root.openAudioOutputDialog();
                        break;
                    case "audioInput":
                        toggleLoader.item.altAction = () => root.openAudioInputDialog();
                        break;
                    }
                }
            }
        }
    }
}
