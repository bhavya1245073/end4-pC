// Lock screen settings.
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
    icon: "lock"
    title: Translation.tr("Lock screen")
    shape: MaterialShape.Shape.Pentagon

    GroupedList {
        ConfigSwitch {
            buttonIcon: "water_drop"
            text: Translation.tr("Use Hyprlock (instead of Quickshell)")
            checked: Config.options.lock.useHyprlock
            onCheckedChanged: { Config.options.lock.useHyprlock = checked }
        }
        ConfigSwitch {
            buttonIcon: "account_circle"
            text: Translation.tr("Launch on startup")
            checked: Config.options.lock.launchOnStartup
            onCheckedChanged: { Config.options.lock.launchOnStartup = checked }
        }
        ConfigSwitch {
            buttonIcon: "widgets"
            enabled: WM.compositor !== "niri"
            text: Translation.tr("Show Widgets")
            checked: Config.options.lock.showWidgets
            onCheckedChanged: { Config.options.lock.showWidgets = checked }
        }
        ConfigSwitch {
            buttonIcon: "tools_installation_kit"
            text: Translation.tr("Show Toolbars")
            checked: Config.options.lock.showToolbars
            onCheckedChanged: { Config.options.lock.showToolbars = checked }
        }
        ConfigSwitch {
            buttonIcon: "music_note"
            enabled: Config.options.lock.showToolbars
            text: Translation.tr("Show media player info")
            checked: Config.options.lock.showMedia
            onCheckedChanged: { Config.options.lock.showMedia = checked }
        }
    }

    ContentSubsection {
        title: Translation.tr("Security")
        GroupedList {
            ConfigSwitch {
                buttonIcon: "settings_power"
                text: Translation.tr("Require password to power off/restart")
                checked: Config.options.lock.security.requirePasswordToPower
                onCheckedChanged: { Config.options.lock.security.requirePasswordToPower = checked }
            }
            ConfigSwitch {
                buttonIcon: "key_vertical"
                text: Translation.tr("Also unlock keyring")
                checked: Config.options.lock.security.unlockKeyring
                onCheckedChanged: { Config.options.lock.security.unlockKeyring = checked }
            }
        }
    }

    ContentSubsection {
        title: Translation.tr("Style: General")
        GroupedList {
            ConfigSwitch {
                buttonIcon: "center_focus_weak"
                text: Translation.tr("Center clock")
                checked: Config.options.lock.centerClock
                onCheckedChanged: { Config.options.lock.centerClock = checked }
            }
            ConfigSwitch {
                buttonIcon: "info"
                text: Translation.tr('Show "Locked" text')
                checked: Config.options.lock.showLockedText
                onCheckedChanged: { Config.options.lock.showLockedText = checked }
            }
            ConfigSwitch {
                buttonIcon: "shapes"
                text: Translation.tr("Use varying shapes for password characters")
                checked: Config.options.lock.materialShapeChars
                onCheckedChanged: { Config.options.lock.materialShapeChars = checked }
            }
        }
    }

    ContentSubsection {
        title: Translation.tr("Style: Blurred")
        GroupedList {
            ConfigSwitch {
                buttonIcon: "blur_on"
                text: Translation.tr("Enable blur")
                checked: Config.options.lock.blur.enable
                onCheckedChanged: { Config.options.lock.blur.enable = checked }
            }
            ConfigSpinBox {
                icon: "deblur"
                text: Translation.tr("Samples")
                value: Config.options.lock.blur.size
                from: 20; to: 200; stepSize: 10
                onValueChanged: { Config.options.lock.blur.size = value }
            }
            ConfigSpinBox {
                icon: "loupe"
                text: Translation.tr("Extra wallpaper zoom (%)")
                value: Config.options.lock.blur.extraZoom * 100
                from: 1; to: 150; stepSize: 2
                onValueChanged: { Config.options.lock.blur.extraZoom = value / 100 }
            }
        }
    }
}
