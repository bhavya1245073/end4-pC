// Wallpaper selector settings.
//
// Injected into Settings -> Interface via `settingsSections` in manifest.json.
// It lives here rather than in the core page so that it disappears when this
// plugin is switched off: controls for a plugin that is not loaded do nothing.
//
// Values still live in the shell's config.json, under `Config.options`, because
// the plugin's own code reads them from there. Only the UI moved.

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.core
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions

ContentSection {
    shape: MaterialShape.Shape.Puffy
    icon: "panorama"
    title: Translation.tr("Wallpaper selector")

    GroupedList {
        ConfigSwitch {
            buttonIcon: "ad"
            text: Translation.tr('Use system file picker')
            checked: Config.options.wallpaperSelector.useSystemFileDialog
            onCheckedChanged: {
                Config.options.wallpaperSelector.useSystemFileDialog = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "home"
            text: Translation.tr('Show home directory in quick access')
            checked: Config.options.wallpaperSelector.showHomePath
            onCheckedChanged: {
                Config.options.wallpaperSelector.showHomePath = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "done"
            text: Translation.tr('Close after selection')
            checked: Config.options.wallpaperSelector.closeAfterSelection
            onCheckedChanged: {
                Config.options.wallpaperSelector.closeAfterSelection = checked;
            }
        }

        ConfigSwitch {
            buttonIcon: "blur_on"
            text: Translation.tr('Show blur background')
            checked: Config.options.wallpaperSelector.showBlurBackground
            onCheckedChanged: {
                Config.options.wallpaperSelector.showBlurBackground = checked;
            }
        }

        ConfigSpinBox {
            icon: "grid_on"
            text: Translation.tr("Columns in grid view")
            value: Config.options.wallpaperSelector.columns
            from: 3
            to: 10
            stepSize: 1
            onValueChanged: {
                Config.options.wallpaperSelector.columns = value;
            }
        }

        ConfigSpinBox {
            icon: "timer"
            text: Translation.tr("Wallpaper change interval (min)")
            value: Config.options.wallpaperSelector.changeInterval / 60000
            from: 0
            to: 1440
            stepSize: 5
            onValueChanged: {
                Config.options.wallpaperSelector.changeInterval = value * 60000;
            }
        }

        ConfigSwitch {
            buttonIcon: "search"
            text: Translation.tr('Always show search bar')
            checked: Config.options.wallpaperSelector.showSearchbar
            onCheckedChanged: {
                Config.options.wallpaperSelector.showSearchbar = checked;
            }
        }
        ConfigTextArea {
            id: userPathField
            Layout.fillWidth: true
            buttonIcon: "folder"
            text: Translation.tr("Custom Wallpaper Folder")
            placeholderText: Translation.tr("e.g., /home/user/Pictures")
            fieldWidth: 300
            value: Config.options.wallpaperSelector.userPath ?? ""

            onValueChanged: {
                userPathDebounceTimer.restart()
            }

            Timer {
                id: userPathDebounceTimer
                interval: 1000
                running: false
                onTriggered: {
                    Config.options.wallpaperSelector.userPath = userPathField.value
                }
            }
        }
        ConfigTextArea {
            id: liveWallpapersPathField
            Layout.fillWidth: true
            buttonIcon: "video_template"
            text: Translation.tr("Live Wallpaper Folder")
            placeholderText: Translation.tr("e.g., /home/user/Videos/Wallpapers")
            fieldWidth: 300
            value: Config.options.wallpaperSelector.liveWallpapersPath ?? ""

            onValueChanged: {
                liveWallpapersPathDebounceTimer.restart()
            }

            Timer {
                id: liveWallpapersPathDebounceTimer
                interval: 1000
                running: false
                onTriggered: {
                    Config.options.wallpaperSelector.liveWallpapersPath = liveWallpapersPathField.value
                }
            }
        } 
    }
}
