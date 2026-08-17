// Loads a plugin's QML and shows the error where the plugin should have been.
//
// The failure this replaces: a typo in a property path - `Appearance.fonts.main` instead of
// `Appearance.font.family.main` - makes a component fail to create. Qt logs one line to the
// journal and carries on. On screen there is simply nothing: an empty gap in the bar, a
// desktop widget that never appears, a pill that does nothing when clicked. Every plugin
// author's first hour is spent discovering that `journalctl --user -u quickshell` is where
// their widget went.
//
// So a failed load draws a small error card instead of nothing:
//
//     [!] gif-picker
//         Cannot assign to non-existent property "colour"
//         GifPickerPanel.qml:41                              [Copy]  [Retry]
//
// Sized to fit where it is (a bar widget's error is a pill, not a card), Material You like
// everything else, and with the full text one click from the clipboard.
//
// ## What this can and cannot catch
//
// It catches everything up to and including component creation: syntax errors, unresolved
// imports, missing types, bad property names, a throw in `Component.onCompleted`. That is
// the great majority of "my plugin does nothing".
//
// It cannot catch a throw inside a signal handler *later* - Qt has no hook for that, and
// there is no equivalent of a JS error boundary re-rendering a subtree. What it does instead
// is make sure such a throw is confined: the handler dies, the shell's event loop does not,
// and PluginErrorBoundary.report() lets any plugin surface its own runtime failure through
// the same UI:
//
//     try { risky() } catch (e) { boundary.report(e) }
//
// ## Isolation is structural, not defensive
//
// Every plugin surface is loaded by its own Loader. One failing leaves its siblings
// untouched because they were never in the same document - the boundary adds the *reporting*,
// not the isolation.

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.core
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root

    // What to load, and who to blame.
    property string pluginId: ""
    property string entry: ""
    property var inject: ({})

    // A label for the surface this boundary is standing in for, used in the error text:
    // "bar widget", "desktop widget", "panel".
    property string surface: ""

    // How much room the error is allowed. `compact` is for a bar: one line, no buttons until
    // hovered. Anything else gets the card.
    property bool compact: false

    // Set false to keep failures invisible - for a probe or a test harness that expects them.
    // Defaults to the shell-wide setting, so a screenshot can hide every error card at once.
    property bool showErrors: Config.options?.plugins?.showErrors ?? true

    readonly property bool failed: root.errorText.length > 0
    readonly property bool loading: loader.status === Loader.Loading
    readonly property Item loadedItem: loader.item

    property string errorText: ""
    property string errorDetail: ""

    // The loaded plugin's size, or the error card's. A boundary that reported its own size as
    // zero would collapse the layout it sits in, which is how a broken bar widget takes the
    // spacing of the whole bar with it.
    implicitWidth: root.failed ? errorLoader.implicitWidth : (loader.item?.implicitWidth ?? 0)
    implicitHeight: root.failed ? errorLoader.implicitHeight : (loader.item?.implicitHeight ?? 0)

    signal failedToLoad(string message);

    function retry(): void {
        root.errorText = "";
        root.errorDetail = "";
        loader.active = false;
        loader.active = true;
    }

    // For a plugin reporting its own runtime failure into the same UI.
    function report(error: var): void {
        const message = (error?.message ?? String(error ?? "")).trim();
        if (message.length === 0)
            return;
        root.errorText = message;
        root.errorDetail = error?.stack ?? "";
        root.failedToLoad(message);
        console.warn(`[plugins] ${root.pluginId}: ${message}`);
    }

    Loader {
        id: loader
        anchors.fill: parent
        active: true
        asynchronous: true
        visible: !root.failed

        function reloadEntry(): void {
            if (!root.entry) {
                loader.setSource("", ({}));
                return;
            }
            root.errorText = "";
            root.errorDetail = "";
            loader.setSource(root.entry, root.inject);
        }

        onStatusChanged: {
            if (loader.status !== Loader.Error)
                return;

            // sourceComponent's errorString is the only place Qt exposes the actual message;
            // the log line is not reachable from QML.
            const raw = loader.sourceComponent?.errorString() ?? "";
            root.errorDetail = raw;
            root.errorText = root.__firstLine(raw) || qsTr("could not be loaded");
            root.failedToLoad(root.errorText);

            // Still logged: the journal is where someone reading a bug report will look, and
            // the on-screen card is deliberately short.
            console.warn(`[plugins] ${root.pluginId} failed to load ${root.entry}\n${raw}`);
        }
    }

    onEntryChanged: loader.reloadEntry()
    Component.onCompleted: loader.reloadEntry()

    // The error UI is itself lazily loaded, so a shell with no broken plugins never builds it.
    Loader {
        id: errorLoader
        anchors.fill: parent
        active: root.failed && root.showErrors
        sourceComponent: root.compact ? compactError : cardError
    }

    // ------------------------------------------------------------------ helpers

    // Qt's errorString is multi-line and starts with a file:// URL. The first useful line is
    // what belongs on screen.
    function __firstLine(raw: string): string {
        const lines = String(raw ?? "").split("\n").map(line => line.trim()).filter(line => line.length > 0);
        if (lines.length === 0)
            return "";
        // "file:///path/Thing.qml:41:5: Cannot assign to non-existent property "colour""
        const match = /^(?:file:\/\/)?(.*?):(\d+)(?::\d+)?:\s*(.*)$/.exec(lines[0]);
        if (!match)
            return lines[0];
        const file = match[1].split("/").pop();
        return `${match[3]} (${file}:${match[2]})`;
    }

    function __copy(): void {
        const text = [
            `plugin: ${root.pluginId}`,
            root.surface ? `surface: ${root.surface}` : "",
            `entry: ${root.entry}`,
            "",
            root.errorDetail || root.errorText
        ].filter(line => line !== "").join("\n");

        PluginUtils.copy(text);
        PluginToast.success(qsTr("Error copied"));
    }

    // ------------------------------------------------------------------- error UI

    Component {
        id: compactError

        Rectangle {
            id: pill

            implicitWidth: pillRow.implicitWidth + Theme.pad.l * 2
            implicitHeight: Math.max(24, pillRow.implicitHeight + Theme.pad.s * 2)
            radius: Theme.radius.full
            color: Theme.errorBlock
            border.width: 1
            border.color: Theme.fade(Theme.error, 0.4)

            MouseArea {
                id: pillMouse
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton)
                        root.retry();
                    else
                        root.__copy();
                }
            }

            StyledToolTip {
                // A MouseArea has containsMouse, not `hovered`, and StyledToolTip treats a missing
                // `hovered` as "always", so the hover test has to be explicit.
                extraVisibleCondition: false
                alternativeVisibleCondition: pillMouse.containsMouse
                text: `${root.pluginId}: ${root.errorText}\n\n`
                    + qsTr("Click to copy, right-click to retry")
            }

            RowLayout {
                id: pillRow
                anchors.centerIn: parent
                spacing: Theme.pad.s

                MaterialSymbol {
                    text: "error"
                    iconSize: Theme.font.m
                    color: Theme.error
                }

                StyledText {
                    text: root.pluginId
                    color: Theme.onErrorBlock
                    font.pixelSize: Theme.font.xs
                    elide: Text.ElideRight
                    Layout.maximumWidth: 90
                }
            }
        }
    }

    Component {
        id: cardError

        Rectangle {
            id: card

            implicitWidth: Math.max(260, cardColumn.implicitWidth + Theme.pad.l * 2)
            implicitHeight: cardColumn.implicitHeight + Theme.pad.l * 2
            radius: Theme.radius.m
            color: Theme.errorBlock
            border.width: 1
            border.color: Theme.fade(Theme.error, 0.35)

            ColumnLayout {
                id: cardColumn
                anchors.fill: parent
                anchors.margins: Theme.pad.l
                spacing: Theme.pad.s

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.pad.m

                    MaterialSymbol {
                        text: "error"
                        iconSize: Theme.font.l
                        color: Theme.error
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.surface
                            ? qsTr("%1 (%2) could not load").arg(root.pluginId).arg(root.surface)
                            : qsTr("%1 could not load").arg(root.pluginId)
                        color: Theme.onErrorBlock
                        font.pixelSize: Theme.font.m
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.maximumWidth: 420
                    text: root.errorText
                    color: Theme.onErrorBlock
                    font.pixelSize: Theme.font.s
                    font.family: Theme.font.mono
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                }

                RowLayout {
                    Layout.topMargin: Theme.pad.xs
                    spacing: Theme.pad.s

                    PluginChip {
                        text: qsTr("Copy log")
                        icon: "content_copy"
                        tone: PluginChip.Tone.Error
                        compact: true
                        onClicked: root.__copy()
                    }

                    PluginChip {
                        text: qsTr("Retry")
                        icon: "refresh"
                        tone: PluginChip.Tone.Neutral
                        compact: true
                        onClicked: root.retry()
                    }

                    PluginChip {
                        visible: root.pluginId.length > 0
                        text: qsTr("Turn off")
                        icon: "toggle_off"
                        tone: PluginChip.Tone.Neutral
                        compact: true
                        onClicked: {
                            PluginRegistry.setEnabled(root.pluginId, false);
                            PluginToast.notice(qsTr("%1 switched off").arg(root.pluginId));
                        }
                    }
                }
            }
        }
    }
}
