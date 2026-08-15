import QtQuick
import QtQuick.Layouts
import qs.core
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: page
    forceWidth: true

    function goTo(term) {
        const needle = term.toLowerCase().trim();

        function findTarget(rootItem) {
            for (let i = 0; i < rootItem.children.length; i++) {
                const child = rootItem.children[i];
                if (child.title && child.title.toLowerCase().includes(needle))
                    return child;
            }
            for (let i = 0; i < rootItem.children.length; i++) {
                const found = findTarget(rootItem.children[i]);
                if (found)
                    return found;
            }
            return null;
        }

        const target = findTarget(mainLayout);
        if (target) {
            const pos = target.mapToItem(mainLayout, 0, 0);
            page.contentY = Math.max(0, pos.y);
        }
    }

    ColumnLayout {
        id: mainLayout
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 20

        ContentSection {
            icon: "extension"
            shape: MaterialShape.Shape.Clover4Leaf
            title: Translation.tr("Installed plugins")

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                text: PluginRegistry.all.length === 0
                    ? Translation.tr("No plugins found in %1").arg(PluginRegistry.pluginsDir)
                    : Translation.tr("%1 plugin(s) found in %2").arg(PluginRegistry.all.length).arg(PluginRegistry.pluginsDir)
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }

            RippleButtonWithIcon {
                Layout.fillWidth: false
                Layout.leftMargin: 8
                materialIcon: "folder_open"
                mainText: Translation.tr("Open plugin folder")
                onClicked: Qt.openUrlExternally(`file://${PluginRegistry.pluginsDir}`)
            }
        }

        ContentSection {
            icon: "error"
            shape: MaterialShape.Shape.Boom
            bgColor: Appearance.colors.colError
            title: Translation.tr("Broken plugins")
            visible: PluginRegistry.errors.length > 0

            Repeater {
                model: PluginRegistry.errors
                delegate: StyledText {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    text: `${modelData.id}: ${modelData.message}`
                    color: Appearance.colors.colOnErrorContainer
                    wrapMode: Text.Wrap
                }
            }
        }

        Repeater {
            model: PluginRegistry.all
            delegate: ContentSection {
                id: pluginSection

                required property var modelData
                readonly property bool supported: PluginRegistry.isSupported(pluginSection.modelData)

                icon: pluginSection.modelData.icon
                shape: MaterialShape.Shape.Cookie7Sided
                title: pluginSection.modelData.name

                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    visible: pluginSection.modelData.description.length > 0
                    text: pluginSection.modelData.description
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    text: {
                        const parts = [pluginSection.modelData.id];
                        if (pluginSection.modelData.version)
                            parts.push(`v${pluginSection.modelData.version}`);
                        if (pluginSection.modelData.author)
                            parts.push(pluginSection.modelData.author);
                        return parts.join("  •  ");
                    }
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    visible: !pluginSection.supported
                    text: PluginRegistry.unsupportedReason(pluginSection.modelData)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnErrorContainer
                    wrapMode: Text.Wrap
                }

                ConfigSwitch {
                    buttonIcon: "power_settings_new"
                    text: Translation.tr("Enabled")
                    enabled: pluginSection.supported
                    checked: PluginRegistry.isEnabled(pluginSection.modelData.id)
                    onCheckedChanged: PluginRegistry.setEnabled(pluginSection.modelData.id, checked)
                }

                PluginSettingsForm {
                    pluginId: pluginSection.modelData.id
                    enabled: PluginRegistry.isActive(pluginSection.modelData.id)
                    opacity: enabled ? 1 : 0.5
                }

                RippleButtonWithIcon {
                    Layout.fillWidth: false
                    Layout.leftMargin: 8
                    visible: pluginSection.modelData.settings.length > 0
                    materialIcon: "restart_alt"
                    mainText: Translation.tr("Reset to defaults")
                    onClicked: PluginConfig.resetAll(pluginSection.modelData.id)
                }
            }
        }
    }
}
