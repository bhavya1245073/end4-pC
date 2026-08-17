pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Io
import qs
import qs.core
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

Scope {
    id: root

    function openCentered(shouldOpen) {
        if (!shouldOpen) {
            PanelRegistry.close("desktopMenu")
            return
        }
        const focusedName = Hyprland.focusedMonitor?.name
        const screen = Quickshell.screens.find(s => s.name === focusedName) ?? Quickshell.screens[0]
        PanelRegistry.open("desktopMenu", { screen: screen, x: screen.width / 2, y: screen.height / 2 })
    }

    function displayPathFor(path) {
        if (!path) return path
        return /\.(mp4|webm|mkv|avi|mov)$/i.test(path)
            ? Config.options.background.thumbnailPath
            : path
    }

    // Wallpaper folder images
    FolderListModel {
        id: wallpaperFolder
        folder: {
            const wallPath = Config.options.background.wallpaperPath
            if (!wallPath || wallPath.length === 0) return ""
            const lastSlash = wallPath.lastIndexOf("/")
            return "file://" + wallPath.substring(0, lastSlash)
        }
        showDirs: false
        nameFilters: ["*.jpg", "*.jpeg", "*.png", "*.webp"]
    }

    property int carouselExtraCount: 5
    property bool useDarkMode: Appearance.m3colors.darkmode
    property var randomWallpapers: {
        const current = FileUtils.trimFileProtocol(Config.options.background.wallpaperPath)
        let all = []
        for (let i = 0; i < wallpaperFolder.count; i++) {
            const fp = FileUtils.trimFileProtocol(wallpaperFolder.get(i, "filePath").toString())
            if (fp !== current) all.push(fp)
        }
        for (let i = all.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [all[i], all[j]] = [all[j], all[i]]
        }
        return all.slice(0, carouselExtraCount)
    }

    property var carouselModel: {
        const current = FileUtils.trimFileProtocol(Config.options.background.wallpaperPath)
        if (!current || current.length === 0) return randomWallpapers.map(p => root.displayPathFor(p))
        return [root.displayPathFor(current), ...randomWallpapers.map(p => root.displayPathFor(p))]
    }

    // Menu window
    Loader {
        active: PanelRegistry.state("desktopMenu").open
        sourceComponent: PanelWindow {
            id: menuWindow

            // Where and on which monitor, from the open request.
            readonly property var openArgs: PanelRegistry.state("desktopMenu").args

            screen: menuWindow.openArgs.screen ?? Quickshell.screens[0]

            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            WlrLayershell.namespace: "quickshell:desktopMenu"
            WlrLayershell.layer: WlrLayer.Overlay

            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }

            // A submenu always arrives as a URL now - the shell's own two included - so there is
            // one loader and one code path instead of a Component for built-ins and a URL for
            // plugins.
            property string openSubmenuUrl: ""
            property real submenuAnchorY: 0
            property real submenuWidth: 284

            Timer {
                id: submenuCloseTimer
                interval: 250
                onTriggered: menuWindow.openSubmenuUrl = ""
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: PanelRegistry.close("desktopMenu")
            }

            // Menu card
            //
            // The shadow and the opaque backing are not decoration: this window floats over the
            // wallpaper and over whatever application is behind it, and a translucent card with no
            // shadow reads as part of that application rather than as a menu.
            StyledRectangularShadow {
                target: menuCard
            }

            Rectangle {
                id: menuCard
                width: 348
                implicitHeight: menuCol.implicitHeight + 16
                x: Math.min(Math.max((menuWindow.openArgs.x ?? menuWindow.width / 2) - width / 2, 8), menuWindow.width - width - 8)
                y: Math.min(Math.max((menuWindow.openArgs.y ?? menuWindow.height / 2) - implicitHeight / 2, 8), menuWindow.height - implicitHeight - 8)
                radius: Appearance.rounding.verylarge
                color: Theme.solid

                // Grows from the pointer, not from its own middle: the menu appears where the click
                // was, and scaling from the centre makes it look like it came from somewhere else.
                transformOrigin: {
                    const localX = (menuWindow.openArgs.x ?? menuWindow.width / 2) - menuCard.x;
                    const localY = (menuWindow.openArgs.y ?? menuWindow.height / 2) - menuCard.y;
                    const left = localX < menuCard.width / 3;
                    const right = localX > menuCard.width * 2 / 3;
                    const top = localY < menuCard.height / 3;
                    const bottom = localY > menuCard.height * 2 / 3;
                    if (top)
                        return left ? Item.TopLeft : right ? Item.TopRight : Item.Top;
                    if (bottom)
                        return left ? Item.BottomLeft : right ? Item.BottomRight : Item.Bottom;
                    return left ? Item.Left : right ? Item.Right : Item.Center;
                }

                scale: 0.85
                opacity: 0

                Component.onCompleted: {
                    scale = 1.0
                    opacity = 1.0
                }

                Behavior on scale {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                }

                ColumnLayout {
                    id: menuCol
                    anchors { fill: parent; margins: 8 }
                    spacing: 4

                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 160
                        radius: Appearance.rounding.verylarge
                        color: Appearance.colors.colLayer0
                        clip: true

                        Carousel {
                            anchors.fill: parent
                            anchors.margins: 10
                            model: root.carouselModel
                            onWallpaperSelected: (path) => {
                                Wallpapers.select(path, Appearance.m3colors.darkmode)
                                PanelRegistry.close("desktopMenu")
                            }
                        }
                    }

                    // Every row in this menu comes from ContextMenuRegistry - the shell's own and
                    // every plugin's, in one list, sorted by `order`, rendered by one delegate.
                    //
                    // There is deliberately no branch on which row this is. A submenu is a URL, an
                    // action is ipc/panel/exec, a count is a bus topic; the shell's rows use the
                    // same four verbs a manifest has, which is the only way to know a plugin row
                    // can do everything a built-in one can.
                    GroupedList {
                        Layout.fillWidth: true
                        itemVerticalPadding: 16
                        bgcolor: Appearance.colors.colLayer0

                        // model/delegate rather than a nested Repeater. A Repeater cannot fill a
                        // `default property list<Item>`: declared children go into that list at
                        // compile time, while a Repeater builds its rows at runtime and parents
                        // them to itself. The list therefore saw one zero-height Item, reported
                        // `implicitHeight: 0`, and the card was sized to the carousel alone - so
                        // every row drew outside it, over the wallpaper, with no background.
                        model: ContextMenuRegistry.all
                        delegate: Component {
                            RippleButton {
                                id: menuRow

                                required property var modelData
                                required property int index

                                readonly property bool opensSubmenu: ContextMenuRegistry.opensSubmenu(menuRow.modelData)
                                readonly property var badge: ContextMenuRegistry.badgeValue(menuRow.modelData)
                                readonly property bool hasBadge: menuRow.badge !== undefined && `${menuRow.badge}`.length > 0 && menuRow.badge !== 0

                                implicitHeight: 40
                                colBackground: "transparent"
                                colBackgroundHover: Appearance.colors.colLayer2

                                // Rows arrive one after another rather than all at once, which reads
                                // as the menu unfolding instead of appearing fully formed. Capped by
                                // Theme.motion so a long list does not end with a row arriving late.
                                PluginAppear { index: menuRow.index }

                                contentItem: RowLayout {
                                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                                    spacing: 12

                                    MaterialSymbol {
                                        text: menuRow.modelData.icon
                                        iconSize: Appearance.font.pixelSize.larger
                                        // Picks up the accent under the pointer, so the row being
                                        // acted on is obvious at a glance.
                                        color: menuRow.hovered ? Theme.accent : Appearance.colors.colOnLayer1

                                        Behavior on color {
                                            animation: Theme.anim.fast.colorAnimation.createObject(this)
                                        }
                                    }

                                    StyledText {
                                        Layout.fillWidth: true
                                        text: menuRow.modelData.label
                                        font.pixelSize: Appearance.font.pixelSize.normal
                                        color: Appearance.colors.colOnLayer1
                                    }

                                    // A row with something to report shows it instead of the
                                    // chevron - the count is the more useful thing in that space.
                                    StyledText {
                                        visible: menuRow.hasBadge
                                        text: `${menuRow.badge}`
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        color: Appearance.colors.colOnLayer1
                                        opacity: 0.6
                                    }

                                    MaterialSymbol {
                                        // A chevron means "there is more here", so only a submenu row
                                        // gets one. A row that opens a panel or runs a command is an
                                        // action, and marking it with a chevron promises a submenu
                                        // that never appears.
                                        visible: !menuRow.hasBadge && menuRow.opensSubmenu
                                        text: "chevron_right"
                                        iconSize: Appearance.font.pixelSize.normal
                                        color: menuRow.hovered ? Theme.accent : Appearance.colors.colOnLayer1
                                        opacity: menuRow.hovered ? 0.8 : 0.4

                                        Behavior on opacity {
                                            animation: Theme.anim.fast.numberAnimation.createObject(this)
                                        }
                                    }
                                }

                                HoverHandler {
                                    enabled: menuRow.opensSubmenu
                                    onHoveredChanged: {
                                        if (!hovered) {
                                            submenuCloseTimer.restart()
                                            return
                                        }
                                        submenuCloseTimer.stop()
                                        menuWindow.submenuAnchorY = menuCard.y + menuRow.mapToItem(menuCard, 0, 0).y
                                        menuWindow.openSubmenuUrl = menuRow.modelData.url
                                    }
                                }

                                onClicked: {
                                    // activate() returns false only for a submenu row, which hover
                                    // has already opened and a click should leave alone.
                                    if (ContextMenuRegistry.activate(menuRow.modelData, menuWindow.openArgs))
                                        PanelRegistry.close("desktopMenu")
                                }
                            }
                        }
                    }
                }
            }

            // SubMenu
            Loader {
                id: submenuLoader
                active: menuWindow.openSubmenuUrl !== ""
                width: menuWindow.submenuWidth
                source: menuWindow.openSubmenuUrl

                x: (menuCard.x + menuCard.width + 8 + menuWindow.submenuWidth > menuWindow.width)
                    ? menuCard.x - menuWindow.submenuWidth - 8
                    : menuCard.x + menuCard.width + 8

                y: Math.min(
                    Math.max(menuWindow.submenuAnchorY, 8),
                    menuWindow.height - (item?.implicitHeight ?? 0) - 8
                )

                scale: active ? 1.0 : 0.9
                opacity: active ? 1.0 : 0.0
                transformOrigin: Item.Center

                Behavior on scale {
                    animation: Appearance.animation.elementMoveEnter.numberAnimation.createObject(this)
                }
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }

                HoverHandler {
                    onHoveredChanged: {
                        if (hovered) submenuCloseTimer.stop()
                        else submenuCloseTimer.restart()
                    }
                }
            }
        }
    }
}