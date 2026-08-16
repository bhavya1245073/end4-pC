pragma Singleton

// Notifications: what arrived, what to do about it, and whether to be quiet.
//
//     PluginNotifications.history        // [{ id, appName, summary, body, icon, image,
//                                        //    urgency, at, actions: [{ id, text, invoke() }] }]
//     PluginNotifications.unreadCount
//     PluginNotifications.dnd            // do not disturb
//     PluginNotifications.toggleDnd()
//     PluginNotifications.dismiss(id)
//     PluginNotifications.clearAll()
//     PluginNotifications.send("Backup finished", "412 files copied")
//
// Entries are plain objects with plain values, so a list delegate never has to guard against
// a Notification that has been destroyed underneath it - which happens, because a
// notification's lifetime is decided by the sending application.
//
// Sending goes through the same helper plugins use directly (PluginUtils.notify), so a
// notification from a plugin is indistinguishable from one sent by any other program - it
// appears in the shell's own popup and history, and is not a private side channel.

import QtQuick
import Quickshell
import qs.services
import qs.core

Singleton {
    id: root

    // -------------------------------------------------------------- reading

    readonly property var history: Notifications.list.map(entry => root.__shape(entry))
    readonly property var popups: Notifications.popupList.map(entry => root.__shape(entry))

    readonly property int count: Notifications.list.length
    readonly property int unreadCount: Notifications.list.filter(entry => entry.popup).length
    readonly property bool hasAny: Notifications.list.length > 0

    // Grouped by application, in the order the shell's own list uses.
    readonly property var byApp: {
        const groups = ({});
        for (const entry of root.history) {
            if (!groups[entry.appName])
                groups[entry.appName] = [];
            groups[entry.appName].push(entry);
        }
        return groups;
    }

    function __shape(entry: var): var {
        return {
            id: entry.notificationId,
            appName: entry.appName,
            summary: entry.summary,
            body: entry.body,
            icon: entry.appIcon,
            image: entry.image,
            urgency: entry.urgency,
            transient: entry.isTransient,
            at: entry.time,
            popup: entry.popup,
            actions: (entry.actions ?? []).map(action => ({
                id: action.identifier,
                text: action.text,
                invoke: () => entry.notification?.actions.find(candidate => candidate.identifier === action.identifier)?.invoke()
            })),
            dismiss: () => Notifications.discardNotification(entry.notificationId)
        };
    }

    // ------------------------------------------------------------- do not disturb

    // The shell's own name for this is `silent`; "dnd" is what everyone calls it.
    property alias dnd: root.__dnd
    property bool __dnd: Notifications.silent
    onDndChanged: Notifications.silent = root.dnd

    function toggleDnd(): void {
        Notifications.silent = !Notifications.silent;
    }

    function setDnd(enabled: bool): void {
        Notifications.silent = enabled;
    }

    // --------------------------------------------------------------- acting

    function dismiss(id: int): void {
        Notifications.discardNotification(id);
    }

    function clearAll(): void {
        Notifications.discardAllNotifications();
    }

    function markAllRead(): void {
        Notifications.markAllRead();
    }

    // Hides the popups without discarding the notifications.
    function dismissPopups(): void {
        Notifications.timeoutAll();
    }

    function invokeAction(id: int, actionId: string): bool {
        const entry = root.history.find(candidate => candidate.id === id);
        const action = entry?.actions.find(candidate => candidate.id === actionId);
        if (!action)
            return false;
        action.invoke();
        return true;
    }

    // --------------------------------------------------------------- sending

    // options: { icon, urgency: "low"|"normal"|"critical", appName, replaceTag }
    function send(title: string, body: string, options: var): void {
        PluginUtils.notify(title, body, options);
    }
}
