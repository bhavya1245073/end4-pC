import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.core

RippleButton {
    id: root
    property bool showPing: false
    property bool vertical: Config.options.bar.vertical
    property bool isMaterial: Config.options.bar.cornerStyle === 3
    property real buttonPadding: 5

    // Hidden when the sidebar has nothing in it, asked of the registry rather than by repeating the
    // three config conditions that used to live here and had to be kept in step with the sidebar.
    visible: SidebarTabRegistry.all.length > 0

    implicitWidth: 32
    implicitHeight: 32

    buttonRadius: Appearance.rounding.full
    colBackground: isMaterial ? Appearance.colors.colPrimaryContainer : "transparent"
    colBackgroundHover: isMaterial ? Appearance.colors.colPrimaryContainerHover : Appearance.colors.colLayer1Hover
    colRipple: isMaterial ? Appearance.colors.colLayer1Active : Appearance.colors.colLayer1Active
    colBackgroundToggled: Appearance.colors.colSecondaryContainer
    colBackgroundToggledHover: Appearance.colors.colSecondaryContainerHover
    colRippleToggled: Appearance.colors.colSecondaryContainerActive
    toggled: PanelRegistry.state("sidebarLeft").open

    onPressed: {
        PanelRegistry.toggle("sidebarLeft");
    }

    Connections {
        target: Ai
        function onResponseFinished() {
            if (PanelRegistry.state("sidebarLeft").open) return;
            root.showPing = true;
        }
    }
    Connections {
        target: Booru
        function onResponseFinished() {
            if (PanelRegistry.state("sidebarLeft").open) return;
            root.showPing = true;
        }
    }
    Connections {
        target: PanelRegistry.state("sidebarLeft")
        function onOpenChanged() {
            root.showPing = false;
        }
    }

    CustomIcon {
        id: distroIcon
        anchors.centerIn: parent
        width: root.isMaterial ? (root.vertical ? 24 : 22) : 19.5
        height: root.isMaterial ? (root.vertical ? 24 : 22) : 19.5
        source: Config.options.custom.distroIcon
        colorize: Config.options.custom.colorizeIcon
        color: Appearance.colors.colPrimary

        Rectangle {
            opacity: root.showPing ? 1 : 0
            visible: opacity > 0
            anchors {
                bottom: parent.bottom
                right: parent.right
                bottomMargin: -2
                rightMargin: -2
            }
            implicitWidth: 8
            implicitHeight: 8
            radius: Appearance.rounding.full
            color: Appearance.colors.colTertiary
            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
        }
    }
}