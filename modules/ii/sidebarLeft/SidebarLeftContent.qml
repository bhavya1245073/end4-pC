import qs.core
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Qt.labs.synchronizer

// The left sidebar's tabs come from SidebarTabRegistry - the shell's four and any a plugin
// contributes, in one list.
//
// This file used to hold two parallel arrays: a list of tab buttons and a list of page Components,
// each with its own copy of the config conditions, kept in the same order by hand. Adding a tab
// meant editing both, and a plugin could not add one at all. Now there is one list and one delegate,
// and a page is a URL - including the shell's own, which is what makes a plugin's tab
// indistinguishable from a built-in one.

Item {
    id: root
    required property var scopeRoot
    property int sidebarPadding: 10
    anchors.fill: parent

    readonly property var tabs: SidebarTabRegistry.all
    readonly property var tabButtonList: SidebarTabRegistry.buttons
    property int tabCount: swipeView.count

    function focusActiveItem() {
        swipeView.currentItem?.forceActiveFocus();
    }

    Keys.onPressed: (event) => {
        if (event.modifiers === Qt.ControlModifier) {
            if (event.key === Qt.Key_PageDown) {
                swipeView.incrementCurrentIndex()
                event.accepted = true;
            }
            else if (event.key === Qt.Key_PageUp) {
                swipeView.decrementCurrentIndex()
                event.accepted = true;
            }
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: sidebarPadding
        }
        spacing: verticalTabBar.expanded ? -2 : 0

        VerticalTabBar {
            id: verticalTabBar
            visible: root.tabButtonList.length > 0
            Layout.fillWidth: true
            tabButtonList: root.tabButtonList
            currentIndex: swipeView.currentIndex
            onCurrentIndexChanged: swipeView.currentIndex = currentIndex
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            implicitWidth: swipeView.implicitWidth
            implicitHeight: swipeView.implicitHeight
            topLeftRadius: 0
            bottomLeftRadius: Appearance.rounding.normal
            topRightRadius: 0
            bottomRightRadius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1

            SwipeView { // Content pages
                id: swipeView
                anchors.fill: parent
                spacing: 10

                clip: true
                layer.enabled: true
                layer.effect: OpacityMask {
                    maskSource: Rectangle {
                        width: swipeView.width
                        height: swipeView.height
                        radius: Appearance.rounding.small
                    }
                }

                Repeater {
                    model: root.tabs

                    // A page per row, loaded from its URL and only once it has been shown:
                    // the AI tab and the anime tab are both expensive, and a sidebar that
                    // loads every tab on open pays for all of them to show one.
                    delegate: Loader {
                        required property var modelData
                        required property int index

                        active: SwipeView.isCurrentItem || SwipeView.isNextItem || SwipeView.isPreviousItem
                        asynchronous: true
                        source: modelData.url

                        onStatusChanged: {
                            if (status === Loader.Error)
                                console.warn(`[sidebar] could not load tab ${modelData.id} from ${modelData.url}`);
                        }
                    }
                }
            }

            // Shown instead of the pages when every tab is switched off, so an empty sidebar says
            // so rather than looking broken.
            ColumnLayout {
                anchors.centerIn: parent
                visible: root.tabs.length === 0
                spacing: Theme.pad.s

                MaterialSymbol {
                    Layout.alignment: Qt.AlignHCenter
                    text: "widgets"
                    iconSize: Theme.font.xl * 1.5
                    color: Theme.textFaint
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    text: Translation.tr("Enjoy your empty sidebar...")
                    color: Appearance.colors.colSubtext
                }
            }
        }
    }
}
