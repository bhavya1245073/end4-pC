// Settings -> Plugins.
//
// Master/detail, not one long scroll. Every plugin used to render its whole
// settings form inline, so the page was the sum of nineteen expanded forms - one
// plugin here has twenty settings on its own - and finding a plugin meant
// scrolling past every setting of every plugin before it.
//
// So: the list is a list. One fixed-height row per plugin with the toggle on it,
// and settings live one tap deeper, where the plugin's name is the title of the
// page instead of a heading somewhere in the middle of a scroll.

import QtQuick
import QtQuick.Layouts
import qs.core
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentPage {
    id: page
    forceWidth: true

    // Empty = the list. Otherwise the id of the plugin being shown.
    property string openPlugin: ""

    readonly property var openManifest: page.openPlugin === "" ? null : PluginRegistry.get(page.openPlugin)

    readonly property var pluginShortcuts: {
        const declared = page.openManifest?.provides?.shortcuts;
        return Array.isArray(declared) ? declared : [];
    }

    // Declared permissions, and the ones the plugin has used without declaring. Both read from
    // PluginPermissions rather than from the manifest directly, so the page shows the same thing
    // the facades enforce.
    readonly property var pluginPermissions: page.openPlugin === "" ? [] : PluginPermissions.declared(page.openPlugin)
    readonly property var undeclaredPermissions: page.openPlugin === "" ? [] : PluginPermissions.undeclared(page.openPlugin)

    // Declared actions, tagged with their `ref` so the row can print the command line.
    readonly property var pluginActions: {
        const declared = page.openManifest?.provides?.actions;
        if (!Array.isArray(declared))
            return [];
        return declared.map(action => Object.assign({ ref: `${page.openPlugin}:${action.id}` }, action));
    }

    property string filter: ""

    readonly property var visiblePlugins: {
        const needle = page.filter.toLowerCase().trim();
        if (needle === "")
            return PluginRegistry.all;
        return PluginRegistry.all.filter(plugin => plugin.name.toLowerCase().includes(needle) || plugin.id.toLowerCase().includes(needle) || (plugin.description ?? "").toLowerCase().includes(needle));
    }

    function show(pluginId) {
        page.openPlugin = pluginId;
        page.contentY = 0;
    }

    function back() {
        page.openPlugin = "";
        page.contentY = 0;
    }

    // The settings search sends us a term. A plugin name is the useful thing to
    // match on, and opening it is more useful than scrolling to it.
    function goTo(term) {
        const needle = term.toLowerCase().trim();
        const hit = PluginRegistry.all.find(plugin => plugin.name.toLowerCase().includes(needle) || plugin.id.toLowerCase().includes(needle));

        if (hit) {
            page.show(hit.id);
            return;
        }

        page.back();
        page.filter = term;
    }

    // Both views live here and cross-fade. Height changes under the fade rather
    // than being animated, so the scroll position never chases a moving target.
    Item {
        Layout.fillWidth: true
        implicitHeight: page.openPlugin === "" ? listView.implicitHeight : detailView.implicitHeight

        ColumnLayout {
            id: listView

            anchors { left: parent.left; right: parent.right; top: parent.top }
            spacing: 20
            opacity: page.openPlugin === "" ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            ContentSection {
                icon: "extension"
                shape: MaterialShape.Shape.Clover4Leaf
                title: Translation.tr("Plugins")

                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    spacing: 8

                    StyledText {
                        Layout.fillWidth: true
                        text: PluginRegistry.all.length === 0 ? Translation.tr("Nothing on %1").arg(PluginRegistry.pluginPaths.join(", ")) : Translation.tr("%1 installed, %2 on").arg(PluginRegistry.all.length).arg(PluginRegistry.activeIds.length)
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                        StyledToolTip {
                            // Which directory a plugin came from decides whether editing it
                            // survives a rebuild, so the paths are worth showing in full.
                            text: PluginRegistry.pluginPaths.map((path, index) => `${index + 1}. ${path}`).join("\n")
                        }
                    }

                    IconToolbarButton {
                        text: "folder_open"
                        // The user directory: the one a plugin can be dropped into without a
                        // rebuild. Created on demand, because opening a missing folder does
                        // nothing at all and looks like a broken button.
                        onClicked: {
                            const userDir = PluginRegistry.userPluginsDir;
                            PluginUtils.exec(["mkdir", "-p", userDir]);
                            Qt.openUrlExternally(`file://${userDir}`);
                        }
                        StyledToolTip { text: Translation.tr("Open %1").arg(PluginRegistry.userPluginsDir) }
                    }
                }

                // Nineteen rows is past the point where scanning beats typing.
                ToolbarTextField {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    visible: PluginRegistry.all.length > 6
                    placeholderText: Translation.tr("Search plugins")
                    text: page.filter
                    onTextChanged: page.filter = text
                }
            }

            ContentSection {
                icon: "error"
                shape: MaterialShape.Shape.Boom
                bgColor: Appearance.colors.colError
                title: Translation.tr("Failed to load")
                visible: PluginRegistry.errors.length > 0

                Repeater {
                    model: PluginRegistry.errors
                    delegate: StyledText {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.leftMargin: 8
                        Layout.rightMargin: 8
                        text: `${modelData.id}: ${modelData.message}`
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnErrorContainer
                        wrapMode: Text.Wrap
                    }
                }
            }

            // One grouped block, rounded at the ends only - the same shape the
            // rest of Settings uses for a list of related rows.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Repeater {
                    model: page.visiblePlugins

                    delegate: Rectangle {
                        id: row

                        required property var modelData
                        required property int index

                        readonly property bool supported: PluginRegistry.isSupported(row.modelData)
                        readonly property bool hasDetail: row.modelData.settings.length > 0 || !row.supported
                        readonly property bool isFirst: row.index === 0
                        readonly property bool isLast: row.index === page.visiblePlugins.length - 1

                        Layout.fillWidth: true
                        implicitHeight: 60
                        color: Appearance.colors.colLayer1
                        topLeftRadius: row.isFirst ? Appearance.rounding.normal : Appearance.rounding.unsharpenmore
                        topRightRadius: row.isFirst ? Appearance.rounding.normal : Appearance.rounding.unsharpenmore
                        bottomLeftRadius: row.isLast ? Appearance.rounding.normal : Appearance.rounding.unsharpenmore
                        bottomRightRadius: row.isLast ? Appearance.rounding.normal : Appearance.rounding.unsharpenmore

                        StateLayer {
                            anchors.fill: parent
                            topLeftRadius: row.topLeftRadius
                            topRightRadius: row.topRightRadius
                            bottomLeftRadius: row.bottomLeftRadius
                            bottomRightRadius: row.bottomRightRadius
                            color: Appearance.colors.colOnLayer1
                            visible: row.hasDetail && rowArea.containsMouse
                        }

                        MouseArea {
                            id: rowArea
                            anchors.fill: parent
                            anchors.rightMargin: 62 // leave the switch its own hit area
                            hoverEnabled: true
                            cursorShape: row.hasDetail ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: if (row.hasDetail) page.show(row.modelData.id)
                        }

                        RowLayout {
                            anchors { fill: parent; leftMargin: 12; rightMargin: 10 }
                            spacing: 12

                            MaterialShapeWrappedMaterialSymbol {
                                text: row.modelData.icon
                                iconSize: Appearance.font.pixelSize.large
                                wrappedShape: MaterialShape.Shape.Cookie7Sided
                                color: row.supported ? Appearance.colors.colSecondaryContainer : Appearance.colors.colError
                            }

                            // Name over description, both single-line: a row that
                            // grows with its description makes the list ragged and
                            // costs more height than the description is worth.
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                StyledText {
                                    Layout.fillWidth: true
                                    text: row.modelData.name
                                    font.pixelSize: Appearance.font.pixelSize.normal
                                    font.weight: Font.Medium
                                    color: Appearance.colors.colOnLayer1
                                    elide: Text.ElideRight
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    visible: text.length > 0
                                    text: row.supported ? row.modelData.description : PluginRegistry.unsupportedReason(row.modelData)
                                    font.pixelSize: Appearance.font.pixelSize.smaller
                                    color: row.supported ? Appearance.colors.colSubtext : Appearance.colors.colOnErrorContainer
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                }
                            }

                            StyledSwitch {
                                Layout.alignment: Qt.AlignVCenter
                                enabled: row.supported
                                checked: PluginRegistry.isEnabled(row.modelData.id)
                                onToggled: PluginRegistry.setEnabled(row.modelData.id, checked)
                                StyledToolTip { text: Translation.tr("Load this plugin") }
                            }

                            MaterialSymbol {
                                Layout.alignment: Qt.AlignVCenter
                                text: "chevron_right"
                                iconSize: Appearance.font.pixelSize.larger
                                color: Appearance.colors.colSubtext
                                opacity: row.hasDetail ? 1 : 0
                            }
                        }
                    }
                }

                // Not PagePlaceholder: that one anchors.fill's its parent and is meant
                // to sit on top of a page, whereas this has to take part in the column.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 30
                    Layout.bottomMargin: 30
                    spacing: 6
                    visible: page.visiblePlugins.length === 0 && PluginRegistry.all.length > 0

                    MaterialShapeWrappedMaterialSymbol {
                        Layout.alignment: Qt.AlignHCenter
                        text: "search_off"
                        iconSize: Appearance.font.pixelSize.huge
                        wrappedShape: MaterialShape.Shape.Clover4Leaf
                        color: Appearance.colors.colSecondaryContainer
                    }

                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        // page?. because this binding outlives the root by a moment when
                        // the page is torn down, and `.arg(undefined)` is not the point.
                        text: Translation.tr("No plugin matches \u201c%1\u201d").arg(page?.filter ?? "")
                        font.pixelSize: Appearance.font.pixelSize.normal
                        color: Appearance.colors.colSubtext
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                    }
                }
            }
        }

        ColumnLayout {
            id: detailView

            anchors { left: parent.left; right: parent.right; top: parent.top }
            spacing: 20
            opacity: page.openPlugin === "" ? 0 : 1
            visible: opacity > 0

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            // The plugin's identity, and the way back. Version, id and author
            // belong here rather than under every row in the list: they matter
            // when you are looking at one plugin, never while scanning for one.
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                IconToolbarButton {
                    text: "arrow_back"
                    onClicked: page.back()
                    StyledToolTip { text: Translation.tr("All plugins") }
                }

                MaterialShapeWrappedMaterialSymbol {
                    text: page.openManifest?.icon ?? "extension"
                    iconSize: Appearance.font.pixelSize.large + 1
                    wrappedShape: MaterialShape.Shape.Cookie7Sided
                    color: Appearance.colors.colSecondaryContainer
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: page.openManifest?.name ?? ""
                        font.pixelSize: Appearance.font.pixelSize.larger
                        font.weight: Font.Medium
                        color: Appearance.colors.colOnSecondaryContainer
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: {
                            if (!page.openManifest)
                                return "";
                            const parts = [page.openManifest.id];
                            if (page.openManifest.version)
                                parts.push(`v${page.openManifest.version}`);
                            if (page.openManifest.author)
                                parts.push(page.openManifest.author);
                            return parts.join("  •  ");
                        }
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colSubtext
                        elide: Text.ElideRight
                    }
                }
            }

            StyledText {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                visible: text.length > 0
                text: page.openManifest?.description ?? ""
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }

            NoticeBox {
                Layout.fillWidth: true
                visible: page.openManifest !== null && !PluginRegistry.isSupported(page.openManifest)
                text: page.openManifest ? PluginRegistry.unsupportedReason(page.openManifest) : ""
            }

            ConfigSwitch {
                id: enableSwitch
                buttonIcon: "power_settings_new"
                text: Translation.tr("Enabled")
                enabled: page.openManifest !== null && PluginRegistry.isSupported(page.openManifest)
                checked: page.openPlugin !== "" && PluginRegistry.isEnabled(page.openPlugin)

                // Deferred to the next tick on purpose. Writing straight from the handler puts the
                // write inside the evaluation of the binding above it: setEnabled recomputes
                // activeIds synchronously, isEnabled changes, and `checked` is re-evaluated while
                // still inside onCheckedChanged - which Qt correctly calls a binding loop. Toggling
                // every plugin off and on in sequence is what made it show up.
                onCheckedChanged: {
                    if (page.openPlugin === "")
                        return;
                    const target = enableSwitch.checked;
                    const plugin = page.openPlugin;
                    Qt.callLater(() => {
                        if (PluginRegistry.isEnabled(plugin) !== target)
                            PluginRegistry.setEnabled(plugin, target);
                    });
                }
            }

            // Settings are dimmed rather than hidden while the plugin is off, so
            // you can set it up before switching it on.
            PluginSettingsForm {
                pluginId: page.openPlugin
                enabled: page.openPlugin !== "" && PluginRegistry.isActive(page.openPlugin)
                opacity: enabled ? 1 : 0.5

                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }

            // What the plugin is allowed to do. Shown before the enable switch on purpose: the
            // point of declaring permissions is that they can be read *before* switching
            // something on, not discovered afterwards.
            ContentSection {
                icon: "shield"
                shape: MaterialShape.Shape.Cookie7Sided
                title: Translation.tr("Permissions")
                visible: page.pluginPermissions.length > 0 || page.undeclaredPermissions.length > 0

                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    text: Translation.tr("Switching one off makes the shell refuse those calls. Plugin code runs in the shell's process, so this is a working off switch rather than a sandbox.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                }

                Repeater {
                    model: page.pluginPermissions

                    delegate: ConfigSwitch {
                        required property string modelData

                        Layout.leftMargin: 8
                        Layout.rightMargin: 8

                        buttonIcon: PluginPermissions.icon(modelData)
                        text: `${PluginPermissions.label(modelData)} \u2014 ${PluginPermissions.summary(modelData)}`
                        checked: page.openPlugin !== "" && PluginPermissions.granted(page.openPlugin, modelData)

                        // Deferred for the same reason the enable switch is: PluginPermissions.set
                        // writes plugins.json, which recomputes `checked` above - and doing that
                        // inside the handler is a write during a binding evaluation.
                        onCheckedChanged: {
                            if (page.openPlugin === "")
                                return;
                            const target = this.checked;
                            const plugin = page.openPlugin;
                            const permission = modelData;
                            Qt.callLater(() => {
                                if (PluginPermissions.granted(plugin, permission) !== target)
                                    PluginPermissions.set(plugin, permission, target);
                            });
                        }
                    }
                }

                // Permissions the plugin has actually exercised without declaring them. Not an
                // error - undeclared use is allowed so this could be added without breaking
                // existing plugins - but worth showing, because the manifest is what the user
                // reads before trusting it.
                NoticeBox {
                    Layout.fillWidth: true
                    visible: page.undeclaredPermissions.length > 0
                    text: Translation.tr("Used without declaring: %1. The manifest should list these.")
                        .arg(page.undeclaredPermissions.map(permission => PluginPermissions.label(permission)).join(", "))
                }
            }

            // Keybinds the plugin declares. Nothing binds a key for you, so listing
            // them is the difference between a usable shortcut and one the user has no
            // way of discovering.
            ContentSection {
                icon: "keyboard"
                shape: MaterialShape.Shape.Cookie7Sided
                title: Translation.tr("Keybinds")
                visible: page.pluginShortcuts.length > 0

                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    text: Translation.tr("Bind these in your compositor config. Under Hyprland: bind = SUPER, K, global, quickshell:<name>")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                }

                Repeater {
                    model: page.pluginShortcuts

                    delegate: PluginRow {
                        required property var modelData

                        Layout.leftMargin: 8
                        Layout.rightMargin: 8

                        icon: "keyboard_command_key"
                        label: modelData.description ?? modelData.id ?? modelData.name ?? ""
                        value: `quickshell:${modelData.id ?? modelData.name ?? ""}`
                    }
                }
            }

            // Actions the plugin declares, with how to call each one. A plugin can be scripted
            // from a terminal or bound to a key without reading its source, which is the whole
            // point of declaring actions - but only if the invocation is written down somewhere.
            ContentSection {
                icon: "bolt"
                shape: MaterialShape.Shape.Cookie7Sided
                title: Translation.tr("Actions")
                visible: page.pluginActions.length > 0

                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 8
                    Layout.rightMargin: 8
                    text: Translation.tr("Callable from the launcher, from another plugin, and from a terminal.")
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                }

                Repeater {
                    model: page.pluginActions

                    delegate: PluginRow {
                        required property var modelData

                        Layout.leftMargin: 8
                        Layout.rightMargin: 8

                        icon: modelData.icon ?? "bolt"
                        label: modelData.label ?? modelData.id ?? ""
                        // The exact command line, arguments included, ready to be copied.
                        value: {
                            const args = Object.keys(modelData.schema ?? {})
                                .map(name => modelData.schema[name]?.required === true ? `${name}=\u2026` : `[${name}=\u2026]`)
                                .join(" ");
                            return `intent call ${modelData.ref}${args ? ` '${args}'` : ""}`;
                        }
                    }
                }
            }

            RippleButtonWithIcon {
                Layout.fillWidth: false
                Layout.leftMargin: 8
                visible: (page.openManifest?.settings.length ?? 0) > 0
                materialIcon: "restart_alt"
                mainText: Translation.tr("Reset to defaults")
                onClicked: PluginConfig.resetAll(page.openPlugin)
            }
        }
    }
}
