pragma Singleton

// What a plugin is allowed to do, declared in its manifest and revocable by the user.
//
//     "permissions": ["network", "clipboard", "storage"]
//
// A permission is not a sandbox. QML plugin code runs in the shell's process and could
// reach anything if it tried, and pretending otherwise would be the dishonest kind of
// security feature. What this *is*:
//
//   - A statement of intent the user can read before switching a plugin on. "This weather
//     widget wants the network and nothing else" is worth knowing.
//   - A revocation switch with real teeth for the facades that route through here. Deny
//     `network` and PluginHttp refuses the request; deny `system-exec` and
//     PluginUtils.run/exec/pipe refuse to spawn; deny `clipboard` and the copy helpers
//     refuse. The plugin is told, the user is told once, and the shell carries on.
//   - A grep-able boundary. A plugin calling a facade it never declared shows up in
//     `scripts/doctor.sh` rather than at runtime on someone else's machine.
//
// Undeclared is *not* denied by default, because that would break every plugin written
// before this existed and turn an additive feature into a migration. An undeclared use is
// granted, recorded, and reported by doctor.sh so it can be declared. A *declared*
// permission the user has switched off is denied, which is the case that has to be exact.

import QtQuick
import Quickshell
import qs.core

Singleton {
    id: root

    // The permissions a manifest may declare. Anything else is a manifest error, caught by
    // the schema rather than here.
    readonly property var known: [
        "network",
        "clipboard",
        "storage",
        "system-exec",
        "notifications",
        "window-manager"
    ]

    readonly property var describe: ({
        "network": {
            label: qsTr("Network"),
            icon: "language",
            summary: qsTr("Fetch data over HTTP through PluginHttp.")
        },
        "clipboard": {
            label: qsTr("Clipboard"),
            icon: "content_paste",
            summary: qsTr("Read and write the clipboard.")
        },
        "storage": {
            label: qsTr("Storage"),
            icon: "save",
            summary: qsTr("Keep state on disk between restarts.")
        },
        "system-exec": {
            label: qsTr("Run programs"),
            icon: "terminal",
            summary: qsTr("Start other programs on your machine.")
        },
        "notifications": {
            label: qsTr("Notifications"),
            icon: "notifications",
            summary: qsTr("Post desktop notifications.")
        },
        "window-manager": {
            label: qsTr("Windows"),
            icon: "select_window",
            summary: qsTr("Inspect and control windows and workspaces.")
        }
    })

    function label(permission: string): string {
        return root.describe[permission]?.label ?? permission;
    }

    function icon(permission: string): string {
        return root.describe[permission]?.icon ?? "help";
    }

    function summary(permission: string): string {
        return root.describe[permission]?.summary ?? "";
    }

    // ------------------------------------------------------------- declaration

    // What the manifest asked for.
    function declared(pluginId: string): var {
        const permissions = PluginRegistry.get(pluginId)?.permissions;
        return Array.isArray(permissions) ? permissions : [];
    }

    function declares(pluginId: string, permission: string): bool {
        return root.declared(pluginId).includes(permission);
    }

    // ------------------------------------------------------------------ grants
    //
    // Stored per plugin under "permissions" in plugins.json, as an object of explicit
    // false entries. Absent means granted, so the file stays empty until someone revokes
    // something and a plugin update that adds a permission is not silently pre-approved as
    // "the user already said yes to everything".

    function granted(pluginId: string, permission: string): bool {
        return PluginConfig.data[pluginId]?.permissions?.[permission] !== false;
    }

    function revoked(pluginId: string, permission: string): bool {
        return !root.granted(pluginId, permission);
    }

    function set(pluginId: string, permission: string, allow: bool): void {
        PluginConfig.mutate(pluginId, entry => {
            const next = Object.assign({}, entry.permissions);
            if (allow) {
                if (next[permission] === undefined)
                    return false;
                delete next[permission];
            } else {
                if (next[permission] === false)
                    return false;
                next[permission] = false;
            }
            entry.permissions = next;
            return true;
        });
    }

    function toggle(pluginId: string, permission: string): void {
        root.set(pluginId, permission, !root.granted(pluginId, permission));
    }

    function grantAll(pluginId: string): void {
        PluginConfig.mutate(pluginId, entry => {
            if (Object.keys(entry.permissions ?? {}).length === 0)
                return false;
            entry.permissions = ({});
            return true;
        });
    }

    // ---------------------------------------------------------------- checking

    // The one facades call. Returns true when the call may proceed.
    //
    // `what` is for the message the user sees when it is refused - "gif-picker was not
    // allowed to reach api.tenor.com" reads better than "permission denied".
    function check(pluginId: string, permission: string, what: string): bool {
        // A facade used from the shell's own code, or from a plugin that did not identify
        // itself, is not something this can rule on.
        if (!pluginId)
            return true;

        if (root.granted(pluginId, permission)) {
            root.__note(pluginId, permission);
            return true;
        }

        console.warn(`[permissions] ${pluginId} was refused "${permission}"`
            + (what ? `: ${what}` : ""));

        // Told once per plugin and permission, not once per call: a denied polling timer
        // would otherwise bury the desktop in toasts.
        const key = `${pluginId}|${permission}`;
        if (!root.__toldAbout.includes(key)) {
            root.__toldAbout = root.__toldAbout.concat([key]);
            PluginToast.show({
                text: qsTr("%1 was blocked: %2").arg(PluginRegistry.get(pluginId)?.name ?? pluginId).arg(root.label(permission)),
                tone: "error",
                icon: "block",
                actionLabel: qsTr("Allow"),
                onAction: () => root.set(pluginId, permission, true),
                pluginId: pluginId
            });
        }
        return false;
    }

    property var __toldAbout: []

    // Permissions actually exercised this session, whether declared or not. doctor.sh reads
    // this over IPC to report manifests that under-declare.
    property var used: ({})

    function __note(pluginId: string, permission: string): void {
        const current = root.used[pluginId] ?? [];
        if (current.includes(permission))
            return;
        const next = Object.assign({}, root.used);
        next[pluginId] = current.concat([permission]);
        root.used = next;
    }

    // Permissions a plugin has used without declaring them.
    function undeclared(pluginId: string): var {
        const declared = root.declared(pluginId);
        return (root.used[pluginId] ?? []).filter(permission => !declared.includes(permission));
    }
}
