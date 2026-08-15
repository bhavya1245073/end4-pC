// Renders one entry of a plugin's `settings` schema as a native settings row.
//
// Plugins get a working GUI from JSON alone - no QML required. A plugin that
// wants more than this can still ship a full `settingsPages` entry.

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

Rectangle {
    id: root

    required property string pluginId
    required property var spec
    required property int index
    required property int count

    readonly property var value: PluginConfig.value(root.pluginId, root.spec.key)
    readonly property string label: root.spec.label ?? root.spec.key
    readonly property bool isFirst: root.index === 0
    readonly property bool isLast: root.index === root.count - 1

    function commit(newValue) {
        PluginConfig.set(root.pluginId, root.spec.key, newValue);
    }

    Layout.fillWidth: true
    implicitHeight: column.implicitHeight + 20
    color: Appearance.colors.colLayer1
    topLeftRadius: root.isFirst ? Appearance.rounding.normal : Appearance.rounding.unsharpenmore
    topRightRadius: root.isFirst ? Appearance.rounding.normal : Appearance.rounding.unsharpenmore
    bottomLeftRadius: root.isLast ? Appearance.rounding.normal : Appearance.rounding.unsharpenmore
    bottomRightRadius: root.isLast ? Appearance.rounding.normal : Appearance.rounding.unsharpenmore

    ColumnLayout {
        id: column
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            margins: 8
        }
        spacing: 2

        Loader {
            Layout.fillWidth: true
            sourceComponent: {
                switch (root.spec.type) {
                case "bool":
                    return boolControl;
                case "int":
                    return intControl;
                case "real":
                    return realControl;
                case "enum":
                    return enumControl;
                default:
                    return stringControl;
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            Layout.leftMargin: 8
            Layout.rightMargin: 8
            visible: (root.spec.description ?? "").length > 0
            text: root.spec.description ?? ""
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
        }
    }

    Component {
        id: boolControl
        ConfigSwitch {
            buttonIcon: root.spec.icon ?? ""
            text: root.label
            checked: root.value === true
            onCheckedChanged: root.commit(checked)
        }
    }

    Component {
        id: intControl
        ConfigSpinBox {
            icon: root.spec.icon ?? ""
            text: root.label
            from: root.spec.min ?? 0
            to: root.spec.max ?? 1000
            stepSize: root.spec.step ?? 1
            value: root.value ?? 0
            onValueChanged: root.commit(value)
        }
    }

    Component {
        id: realControl
        ConfigSlider {
            buttonIcon: root.spec.icon ?? ""
            text: root.label
            from: root.spec.min ?? 0
            to: root.spec.max ?? 1
            usePercentTooltip: (root.spec.max ?? 1) <= 1
            value: root.value ?? 0
            onValueChanged: root.commit(value)
        }
    }

    Component {
        id: enumControl
        ConfigComboBox {
            buttonIcon: root.spec.icon ?? ""
            text: root.label
            currentValue: root.value
            model: (root.spec.options ?? []).map(option => ({
                        value: option.value,
                        displayName: option.label ?? option.value
                    }))
            onSelected: newValue => root.commit(newValue)
        }
    }

    Component {
        id: stringControl
        ConfigTextArea {
            buttonIcon: root.spec.icon ?? ""
            text: root.label
            placeholderText: root.spec.placeholder ?? ""
            value: root.value ?? ""
            confirmButtonVisible: value !== (root.value ?? "")
            onConfirmClicked: root.commit(value)
        }
    }
}
